import Foundation
import CryptoKit
import Security
import AssistantCore

struct CompanionConnection: Codable, Equatable, Sendable {
    var baseURL: URL
    var certificateSHA256: String
    var serverID: String
    var deviceID: String
    var profileID: String
    var name: String
    var credentialAccount: String { "companion:" + serverID + ":" + deviceID }
    var destination: String { "computer:" + serverID + ":chatgpt:" + profileID }
}

/// The scanned certificate is the identity pin for this single connection.
/// Never accept another certificate or follow a redirect with the device token.
/// Info.plist permits this manual trust policy on Tailscale's address range;
/// NSAllowsLocalNetworking alone does not cover those CGNAT addresses.
final class CompanionTLS: NSObject, URLSessionDelegate, URLSessionTaskDelegate, Sendable {
    let host: String
    let fingerprint: String
    init(host: String, fingerprint: String) { self.host = host; self.fingerprint = fingerprint }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host == host, let trust = challenge.protectionSpace.serverTrust,
              let certificates = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = certificates.first else {
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        let data = SecCertificateCopyData(leaf) as Data
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == fingerprint else { completionHandler(.cancelAuthenticationChallenge, nil); return }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}

struct CompanionClient: Sendable {
    let baseURL: URL
    let token: String
    let session: URLSession
    init(baseURL: URL, fingerprint: String, token: String) throws {
        guard baseURL.scheme == "https", let host = baseURL.host, baseURL.user == nil, baseURL.password == nil,
              baseURL.query == nil, baseURL.fragment == nil, ["", "/"].contains(baseURL.path),
              fingerprint.count == 64, fingerprint.allSatisfy(\.isHexDigit), !token.contains(where: \.isNewline) else {
            throw AssistantError.provider("Scan the connection code shown by Personal Assistant Computer.")
        }
        self.baseURL = baseURL; self.token = token
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 35; config.timeoutIntervalForResource = 90
        config.httpCookieStorage = nil; config.urlCache = nil; config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config, delegate: CompanionTLS(host: host, fingerprint: fingerprint.lowercased()), delegateQueue: nil)
    }
    func data(_ path: String, method: String = "GET", body: JSONValue? = nil) async throws -> Data {
        guard path.hasPrefix("/v1/"), !path.contains(".."), let url = URL(string: path, relativeTo: baseURL)?.absoluteURL,
              url.host == baseURL.host, url.port == baseURL.port else { throw AssistantError.provider("The computer request is invalid.") }
        var request = URLRequest(url: url); request.httpMethod = method
        if !token.isEmpty { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONEncoder().encode(body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: request)
        guard data.count <= 40 * 1024 * 1024, let response = response as? HTTPURLResponse else { throw AssistantError.provider("The computer returned an invalid response.") }
        guard (200..<300).contains(response.statusCode) else {
            let text = (try? JSONDecoder().decode(JSONValue.self, from: data))?["error"]?.stringValue
            throw AssistantError.provider(text ?? "The computer connection needs attention (\(response.statusCode)).")
        }
        return data
    }
    func json(_ path: String, method: String = "GET", body: JSONValue? = nil) async throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: await data(path, method: method, body: body))
    }
    static func pair(_ text: String, deviceName: String) async throws -> (CompanionConnection, String) {
        guard text.utf8.count < 8192, let payload = try? JSONValue.parse(text),
              let rawURL = payload["base_url"]?.stringValue, let url = URL(string: rawURL),
              let fingerprint = payload["certificate_sha256"]?.stringValue, let server = payload["server_id"]?.stringValue,
              let code = payload["pairing_code"]?.stringValue else { throw AssistantError.provider("This is not a computer connection code.") }
        let client = try CompanionClient(baseURL: url, fingerprint: fingerprint, token: "")
        let value = try await client.json("/v1/pair", method: "POST", body: .object(["pairing_code": .string(code), "device_name": .string(deviceName)]))
        guard value["server_id"]?.stringValue == server, let device = value["device_id"]?.stringValue,
              let token = value["credential"]?.stringValue, let profile = value["profile_id"]?.stringValue else {
            throw AssistantError.provider("Sign in to ChatGPT on the computer, then create a new connection code.")
        }
        return (CompanionConnection(baseURL: url, certificateSHA256: fingerprint, serverID: server, deviceID: device, profileID: profile, name: "Your computer"), token)
    }
}
