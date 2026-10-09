import AssistantCore
import AuthenticationServices
import CryptoKit
import Foundation
import Network
import Security
import UIKit

/// Apple's authentication browser remains onscreen while a loopback-only listener receives OpenAI's documented callback.
@MainActor
final class ChatGPTSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var receiver: AccountCallbackReceiver?
    private var anchor: ASPresentationAnchor?
    private var active = false

    func connect(service: ChatGPTAccountService, clientID: String? = nil) async throws -> String {
        guard !active else { throw AssistantError.busy }
        active = true
        defer { active = false; session?.cancel(); session = nil; receiver?.stop(); receiver = nil; anchor = nil }
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows).first(where: \.isKeyWindow) else { throw AccountConnectionError.unavailable }
        anchor = window
        let receiver = AccountCallbackReceiver()
        self.receiver = receiver
        let redirect = try await receiver.start()
        let context = await service.authorizationContext(clientID: clientID)
        let verifier = try Self.randomValue(bytes: 48)
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let attempt = try ChatGPTAuthorizationAttempt(state: Self.randomValue(), nonce: Self.randomValue(),
            verifier: verifier, challenge: challenge, redirectURI: redirect, hostID: context.hostID, clientID: clientID)
        receiver.prepare(attempt)
        let session = ASWebAuthenticationSession(url: attempt.authorizationURL(idTokenHint: context.hint, emailHint: context.email),
            callback: .customScheme("dev.jacob.personalassistant.auth-finished")) { [weak receiver] _, _ in
                Task { @MainActor in receiver?.cancel() }
            }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        self.session = session
        guard session.start() else { throw AccountConnectionError.unavailable }
        let code = try await withTaskCancellationHandler {
            try await receiver.callback()
        } onCancel: { Task { @MainActor in receiver.cancel() } }
        // The browser never receives access/refresh tokens. The loopback authorization code is redeemed natively.
        session.cancel()
        try Task.checkCancellation()
        return try await service.finish(code, attempt: attempt)
    }
    func cancel() { receiver?.cancel(); session?.cancel() }
    // connect establishes and retains this window before starting the authentication session.
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { anchor! }
    private static func randomValue(bytes: Int = 32) throws -> String {
        var buffer = [UInt8](repeating: 0, count: bytes)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes, &buffer) == errSecSuccess else { throw AccountConnectionError.unavailable }
        return base64URL(Data(buffer))
    }
    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

@MainActor
final class AccountCallbackReceiver {
    private var listener: NWListener?
    private var ready: CheckedContinuation<URL, Error>?
    private var waiting: CheckedContinuation<ChatGPTAuthorizationCode, Error>?
    private var result: Result<ChatGPTAuthorizationCode, Error>?
    private var attempt: ChatGPTAuthorizationAttempt?
    private var timeout: Task<Void, Never>?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private let queue = DispatchQueue(label: "assistant.oauth.loopback")

    func start() async throws -> URL {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in self?.stateChanged(state) }
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(600))
            if !Task.isCancelled { self?.finish(.failure(ChatGPTAuthorizationError.expiredAttempt)) }
        }
        return try await withCheckedThrowingContinuation { continuation in
            ready = continuation
            listener.start(queue: queue)
        }
    }
    func prepare(_ attempt: ChatGPTAuthorizationAttempt) { self.attempt = attempt }
    func callback() async throws -> ChatGPTAuthorizationCode {
        if let result { return try result.get() }
        return try await withCheckedThrowingContinuation { waiting = $0 }
    }
    func cancel() { finish(.failure(CancellationError())) }
    func stop() {
        timeout?.cancel(); timeout = nil
        listener?.cancel(); listener = nil
        for connection in connections.values { connection.cancel() }
        connections = [:]
        if let ready { self.ready = nil; ready.resume(throwing: CancellationError()) }
        if let waiting { self.waiting = nil; waiting.resume(throwing: CancellationError()) }
    }
    private func stateChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            if let port = listener?.port, let continuation = ready {
                ready = nil
                continuation.resume(returning: URL(string: "http://127.0.0.1:\(port.rawValue)/auth/callback")!)
            }
        case .failed: finish(.failure(AccountConnectionError.unavailable))
        default: break
        }
    }
    private func finish(_ value: Result<ChatGPTAuthorizationCode, Error>) {
        guard result == nil else { return }
        result = value
        if let waiting { self.waiting = nil; waiting.resume(with: value) }
        if let ready { self.ready = nil; ready.resume(throwing: AccountConnectionError.unavailable) }
        timeout?.cancel(); timeout = nil
    }
    private func accept(_ connection: NWConnection) {
        guard result == nil, connections.count < 4 else { connection.cancel(); return }
        connections[ObjectIdentifier(connection)] = connection
        connection.start(queue: queue)
        receive(connection, buffer: Data())
        Task { [weak self, weak connection] in
            try? await Task.sleep(for: .seconds(10))
            if let self, let connection, self.connections[ObjectIdentifier(connection)] != nil {
                self.close(connection)
            }
        }
    }
    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, self.result == nil else { connection.cancel(); return }
                var next = buffer
                if let data { next.append(data) }
                guard next.count <= 16_384, error == nil else { self.close(connection); return }
                if let text = String(data: next, encoding: .utf8), text.contains("\r\n\r\n") {
                    self.handle(text, connection: connection)
                } else if complete { self.close(connection) }
                else { self.receive(connection, buffer: next) }
            }
        }
    }
    private func handle(_ request: String, connection: NWConnection) {
        guard let attempt else { reply(connection, success: false); return }
        let lines = request.components(separatedBy: "\r\n")
        let fields = (lines.first ?? "").split(separator: " ")
        let host = lines.first { $0.lowercased().hasPrefix("host:") }?.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard fields.count == 3, fields[0] == "GET", fields[2] == "HTTP/1.1",
              host == "127.0.0.1:\(attempt.redirectURI.port!)", fields[1].hasPrefix("/auth/callback?"),
              let url = URL(string: "http://127.0.0.1:\(attempt.redirectURI.port!)" + String(fields[1])) else {
            reply(connection, success: false); return
        }
        do {
            let code = try attempt.validateCallback(url)
            reply(connection, success: true)
            finish(.success(code))
        } catch ChatGPTAuthorizationError.denied {
            reply(connection, success: false)
            finish(.failure(ChatGPTAuthorizationError.denied))
        } catch { reply(connection, success: false) }
    }
    private func reply(_ connection: NWConnection, success: Bool) {
        let body = success ? "Sign-in received. Return to Personal Assistant." : "This callback could not be verified."
        let status = success ? "200 OK" : "400 Bad Request"
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { [weak self] _ in
            Task { @MainActor in self?.close(connection) }
        })
    }
    private func close(_ connection: NWConnection) {
        connection.cancel(); connections[ObjectIdentifier(connection)] = nil
    }
}
