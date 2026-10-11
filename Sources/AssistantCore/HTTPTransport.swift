import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol HTTPStreamingTransport: Sendable {
    func stream(_ request: URLRequest) -> AsyncThrowingStream<Data, any Error>
}

public struct URLSessionStreamingTransport: HTTPStreamingTransport {
    public init() {}
    public func stream(_ request: URLRequest) -> AsyncThrowingStream<Data, any Error> {
        AsyncThrowingStream { continuation in
            let delegate = StreamDelegate(continuation: continuation)
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 120
            configuration.timeoutIntervalForResource = 900
            configuration.httpCookieStorage = nil
            configuration.urlCache = nil
            let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
            delegate.session = session
            let task = session.dataTask(with: request)
            continuation.onTermination = { @Sendable _ in task.cancel(); session.invalidateAndCancel() }
            task.resume()
        }
    }
}

/// URLSession serializes delegate callbacks. Mutable state is confined to that queue after setup.
private final class StreamDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    let continuation: AsyncThrowingStream<Data, any Error>.Continuation
    var session: URLSession?
    var statusCode = 0
    var retryAfter: Double?
    var errorBody = Data()
    init(continuation: AsyncThrowingStream<Data, any Error>.Continuation) { self.continuation = continuation }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        retryAfter = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if (200..<300).contains(statusCode) { continuation.yield(data) }
        else if errorBody.count < 2048 { errorBody.append(data.prefix(2048 - errorBody.count)) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        defer { session.finishTasksAndInvalidate(); self.session = nil }
        if let error { continuation.finish(throwing: error) }
        else if !(200..<300).contains(statusCode) {
            // Do not log credentials, prompts, response bodies, or arbitrary server-provided instructions.
            let code = (try? JSONValue.parse(String(decoding: errorBody, as: UTF8.self)))?["error"]?["code"]?.stringValue
            continuation.finish(throwing: ModelHTTPError(status: statusCode, retryAfter: retryAfter, code: code))
        } else { continuation.finish() }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        // Model requests contain private content and often credentials. Never follow an unexpected redirect.
        completionHandler(nil)
    }
}

public enum EndpointPolicy {
    public static func validate(_ baseURL: URL) throws {
        guard let host = baseURL.host?.lowercased(), !host.isEmpty,
              baseURL.user == nil, baseURL.password == nil, baseURL.query == nil, baseURL.fragment == nil else {
            throw AssistantError.invalidEndpoint("Use a server base URL without embedded credentials, query parameters, or fragments.")
        }
        if baseURL.scheme?.lowercased() == "https" { return }
        guard baseURL.scheme?.lowercased() == "http", isLocalHost(host) else {
            throw AssistantError.invalidEndpoint("Use HTTPS for internet endpoints. HTTP is allowed only for loopback or private LAN addresses.")
        }
    }
    public static func isLocalHost(_ host: String) -> Bool {
        if ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host) { return true }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        let octets = parts.compactMap { Int($0) }
        guard parts.count == 4, octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else { return false }
        guard zip(parts, octets).allSatisfy({ String($0.1) == $0.0 }) else { return false }
        return octets[0] == 10 || (octets[0] == 172 && (16...31).contains(octets[1]))
            || (octets[0] == 192 && octets[1] == 168)
    }
}
