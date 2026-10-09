import AssistantCore
import Foundation
import JOSESwift
import Security

struct ChatGPTAccountSummary: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let isConnected: Bool
}
private struct AccountTokens: Codable, Sendable {
    var accessToken: String
    var refreshToken: String
    var idToken: String
    var scopes: Set<String>
    var expiresAt: Date
}
private struct AccountRegistration: Codable, Sendable {
    var clientID: String
    var subject: String
    var email: String?
    var tokens: AccountTokens?
    var lastSelectedModel: String?
}
private struct AccountVault: Codable, Sendable {
    var hostID = "urn:uuid:" + UUID().uuidString.lowercased()
    var registrations: [AccountRegistration] = []
    var selectedClientID: String?
}
private struct TokenResponse: Decodable, Sendable {
    var access_token: String
    var refresh_token: String?
    var id_token: String?
    var token_type: String
    var expires_in: Double
    var scope: String?
}

enum AccountConnectionError: LocalizedError {
    case signInRequired, network(Int), revoked, unavailable
    var errorDescription: String? {
        switch self {
        case .signInRequired: "Connect this ChatGPT account again to continue. Your conversations are saved."
        case .network(let status): "ChatGPT connection returned HTTP \(status). Try again or check this app's access in ChatGPT settings."
        case .revoked: "ChatGPT requires a fresh sign-in. Your conversations are saved."
        case .unavailable: "The ChatGPT connection is unavailable. Try again."
        }
    }
}

/// All token replacement is atomic in Keychain; a single refresh task owns each rotating session.
actor ChatGPTAccountService {
    private static let vaultKey = "chatgpt-account-vault-v1"
    private var vault: AccountVault
    private var refreshes: [String: Task<AccountRegistration, Error>] = [:]
    private var signedOut = Set<String>()
    private var jwks: (Date, JSONValue)?

    init() throws {
        let raw = try CredentialStore.read(account: Self.vaultKey)
        vault = raw.isEmpty ? AccountVault() : try JSONDecoder().decode(AccountVault.self, from: Data(raw.utf8))
        if raw.isEmpty { try CredentialStore.save(String(decoding: JSONEncoder().encode(vault), as: UTF8.self), account: Self.vaultKey) }
    }
    func summaries() -> [ChatGPTAccountSummary] {
        vault.registrations.map { registration in
            let suffix = String(registration.clientID.suffix(6))
            return ChatGPTAccountSummary(id: registration.clientID, label: (registration.email ?? "ChatGPT account") + " · " + suffix,
                                         isConnected: registration.tokens != nil)
        }
    }
    func selectedID() -> String? { vault.selectedClientID }
    func authorizationContext(clientID: String?) -> (hostID: String, hint: String?, email: String?) {
        let account = vault.registrations.first { $0.clientID == clientID }
        return (vault.hostID, account?.tokens?.idToken, account?.email)
    }
    func select(_ id: String) throws {
        guard vault.registrations.contains(where: { $0.clientID == id && $0.tokens != nil }) else { throw AccountConnectionError.signInRequired }
        vault.selectedClientID = id; try save()
    }
    func finish(_ code: ChatGPTAuthorizationCode, attempt: ChatGPTAuthorizationAttempt) async throws -> String {
        let data = try await AccountHTTP.request(url: URL(string: "https://auth.openai.com/api/accounts/oauth/token")!, body: code.exchangeForm)
        let response = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard let idToken = response.id_token, let refresh = response.refresh_token else { throw ChatGPTAuthorizationError.invalidResponse }
        let expected = attempt.clientID.flatMap { id in vault.registrations.first { $0.clientID == id }?.subject }
        let identity = try await verify(idToken, clientID: code.clientID, nonce: attempt.nonce, expectedSubject: expected)
        let tokens = try tokenRecord(response, idToken: idToken, refresh: refresh, previousScopes: nil)
        let registration = AccountRegistration(clientID: code.clientID, subject: identity.subject, email: identity.email, tokens: tokens)
        if let index = vault.registrations.firstIndex(where: { $0.clientID == code.clientID }) {
            guard vault.registrations[index].subject == identity.subject else { throw ChatGPTAuthorizationError.invalidIdentity }
            vault.registrations[index] = registration
        } else { vault.registrations.append(registration) }
        signedOut.remove(code.clientID)
        vault.selectedClientID = code.clientID
        try save()
        return code.clientID
    }
    func models(for id: String) async throws -> [ChatGPTModel] {
        let access = try await accessToken(for: id)
        let data = try await AccountHTTP.request(url: URL(string: "https://api.openai.com/v1/models")!, token: access)
        return try ChatGPTModel.catalog(from: data)
    }
    func accessToken(for id: String) async throws -> String {
        guard let account = vault.registrations.first(where: { $0.clientID == id }), let tokens = account.tokens,
              !signedOut.contains(id) else { throw AccountConnectionError.signInRequired }
        if tokens.expiresAt.timeIntervalSinceNow > 90 { return tokens.accessToken }
        let task = refreshes[id] ?? Task { try await self.refresh(account) }
        refreshes[id] = task
        defer { refreshes[id] = nil }
        let renewed = try await task.value
        guard !signedOut.contains(id), let index = vault.registrations.firstIndex(where: { $0.clientID == id }) else {
            throw AccountConnectionError.signInRequired
        }
        vault.registrations[index] = renewed
        try save()
        return renewed.tokens!.accessToken
    }
    func signOut(_ id: String, revokeRemotely: Bool = true) async throws -> Bool {
        guard let account = vault.registrations.first(where: { $0.clientID == id }) else { return true }
        signedOut.insert(id)
        var sessionToRevoke = account.tokens
        if let refresh = refreshes[id], let renewed = try? await refresh.value { sessionToRevoke = renewed.tokens }
        refreshes[id] = nil
        var confirmed = sessionToRevoke == nil
        if revokeRemotely, let token = sessionToRevoke?.refreshToken {
            do {
                let configuration = try await discovery()
                guard let endpoint = configuration["revocation_endpoint"]?.stringValue, let url = URL(string: endpoint), url.host == "auth.openai.com" else { throw AccountConnectionError.unavailable }
                _ = try await AccountHTTP.request(url: url, body: OAuthForm.encode(["token": token, "token_type_hint": "refresh_token", "client_id": id]))
                confirmed = true
            } catch { confirmed = false }
        }
        if let index = vault.registrations.firstIndex(where: { $0.clientID == id }) { vault.registrations[index].tokens = nil }
        if vault.selectedClientID == id { vault.selectedClientID = nil }
        try save()
        return confirmed
    }
    private func refresh(_ account: AccountRegistration) async throws -> AccountRegistration {
        guard let tokens = account.tokens else { throw AccountConnectionError.signInRequired }
        let data = try await AccountHTTP.request(url: URL(string: "https://auth.openai.com/api/accounts/oauth/token")!,
            body: OAuthForm.encode(["grant_type": "refresh_token", "client_id": account.clientID,
                                    "refresh_token": tokens.refreshToken, "resource": "https://api.openai.com/v1"]))
        let response = try JSONDecoder().decode(TokenResponse.self, from: data)
        if let idToken = response.id_token {
            _ = try await verify(idToken, clientID: account.clientID, nonce: nil, expectedSubject: account.subject)
        }
        var renewed = account
        renewed.tokens = try tokenRecord(response, idToken: response.id_token ?? tokens.idToken,
                                         refresh: response.refresh_token ?? tokens.refreshToken, previousScopes: tokens.scopes)
        return renewed
    }
    private func tokenRecord(_ response: TokenResponse, idToken: String, refresh: String, previousScopes: Set<String>?) throws -> AccountTokens {
        let scopes = response.scope.map { Set($0.split(separator: " ").map(String.init)) } ?? previousScopes ?? []
        guard scopes.contains("chatgpt.tokens.use.direct"), scopes.contains("resource.invoke") else { throw ChatGPTAuthorizationError.planNotGranted }
        guard response.token_type.caseInsensitiveCompare("Bearer") == .orderedSame, !response.access_token.isEmpty,
              !refresh.isEmpty, response.expires_in > 0, response.expires_in.isFinite else { throw ChatGPTAuthorizationError.invalidResponse }
        return AccountTokens(accessToken: response.access_token, refreshToken: refresh, idToken: idToken, scopes: scopes,
                             expiresAt: Date().addingTimeInterval(response.expires_in))
    }
    private func discovery() async throws -> JSONValue {
        let data = try await AccountHTTP.request(url: URL(string: "https://auth.openai.com/.well-known/openid-configuration")!)
        let configuration = try JSONDecoder().decode(JSONValue.self, from: data)
        guard configuration["issuer"]?.stringValue == "https://auth.openai.com" else { throw ChatGPTAuthorizationError.invalidIdentity }
        return configuration
    }
    private func verify(_ token: String, clientID: String, nonce: String?, expectedSubject: String?) async throws -> (subject: String, email: String?) {
        do {
            guard token.utf8.count < 128 * 1024 else { throw ChatGPTAuthorizationError.invalidIdentity }
            let signed = try JWS(compactSerialization: token)
            guard signed.header.algorithm == .RS256, signed.header.crit == nil,
                  OpenAIIDTokenVerifier.usesStandardPayloadEncoding(token), let kid = signed.header.kid else { throw ChatGPTAuthorizationError.invalidIdentity }
            var keys = jwks?.1
            if jwks == nil || Date().timeIntervalSince(jwks!.0) > 300 || keys?["keys"]?.arrayValue?.contains(where: { $0["kid"]?.stringValue == kid }) != true {
                let configuration = try await discovery()
                guard let value = configuration["jwks_uri"]?.stringValue, let url = URL(string: value), url.host == "auth.openai.com" else { throw ChatGPTAuthorizationError.invalidIdentity }
                keys = try JSONDecoder().decode(JSONValue.self, from: await AccountHTTP.request(url: url))
                jwks = (Date(), keys!)
            }
            return try OpenAIIDTokenVerifier.verify(token, jwks: keys ?? .null, clientID: clientID, nonce: nonce, expectedSubject: expectedSubject)
        } catch {
            // JOSE parser errors can contain token components. Never expose their descriptions.
            throw ChatGPTAuthorizationError.invalidIdentity
        }
    }
    private func save() throws {
        try CredentialStore.save(String(decoding: JSONEncoder().encode(vault), as: UTF8.self), account: Self.vaultKey)
    }
}

enum OpenAIIDTokenVerifier {
    static func usesStandardPayloadEncoding(_ token: String) -> Bool {
        guard let component = token.split(separator: ".").first else { return false }
        var base64 = component.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64), let header = try? JSONDecoder().decode(JSONValue.self, from: data) else { return false }
        return header["b64"] == nil
    }
    static func verify(_ token: String, jwks: JSONValue, clientID: String, nonce: String?, expectedSubject: String? = nil) throws -> (subject: String, email: String?) {
        do {
            guard token.utf8.count < 128 * 1024 else { throw ChatGPTAuthorizationError.invalidIdentity }
            let signed = try JWS(compactSerialization: token)
            guard signed.header.algorithm == .RS256, signed.header.crit == nil,
                  usesStandardPayloadEncoding(token), let kid = signed.header.kid else { throw ChatGPTAuthorizationError.invalidIdentity }
            let matching = jwks["keys"]?.arrayValue?.filter { $0["kid"]?.stringValue == kid && $0["kty"]?.stringValue == "RSA" } ?? []
            guard matching.count == 1 else { throw ChatGPTAuthorizationError.invalidIdentity }
            let key = matching[0]
            guard key["alg"] == nil || key["alg"]?.stringValue == "RS256",
                  key["use"] == nil || key["use"]?.stringValue == "sig",
                  key["key_ops"] == nil || key["key_ops"]?.arrayValue?.contains(.string("verify")) == true else { throw ChatGPTAuthorizationError.invalidIdentity }
            let jwk = try RSAPublicKey(data: JSONEncoder().encode(key))
            let publicKey = try jwk.converted(to: SecKey.self)
            guard let verifier = Verifier(signatureAlgorithm: .RS256, key: publicKey) else { throw ChatGPTAuthorizationError.invalidIdentity }
            let verified = try signed.validate(using: verifier)
            let claims = try JSONDecoder().decode(JSONValue.self, from: verified.payload.data())
            return try ChatGPTIdentityClaims.validate(claims, clientID: clientID, nonce: nonce, expectedSubject: expectedSubject)
        } catch { throw ChatGPTAuthorizationError.invalidIdentity }
    }
}

private enum AccountHTTP {
    static func request(url: URL, body: Data? = nil, token: String? = nil) async throws -> Data {
        guard url.scheme == "https", ["auth.openai.com", "api.openai.com"].contains(url.host ?? ""),
              url.user == nil, url.password == nil, url.fragment == nil else { throw AccountConnectionError.unavailable }
        var request = URLRequest(url: url)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type") }
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 30; configuration.timeoutIntervalForResource = 60
        let session = URLSession(configuration: configuration, delegate: NoAccountRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw AccountConnectionError.unavailable }
        guard (200..<300).contains(http.statusCode) else { throw AccountConnectionError.network(http.statusCode) }
        guard data.count <= 2 * 1024 * 1024 else { throw ChatGPTAuthorizationError.invalidResponse }
        return data
    }
}
private final class NoAccountRedirect: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
