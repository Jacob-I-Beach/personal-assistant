import Foundation

public enum ChatGPTAuthorizationError: Error, LocalizedError, Equatable, Sendable {
    case invalidCallback, expiredAttempt, denied, incompleteRegistration, invalidIdentity, planNotGranted, invalidResponse
    public var errorDescription: String? {
        switch self {
        case .invalidCallback: "ChatGPT sign-in could not be verified. Start a fresh sign-in."
        case .expiredAttempt: "This sign-in attempt expired. Continue with ChatGPT again."
        case .denied: "ChatGPT access was not approved. You can continue using an on-device model."
        case .incompleteRegistration: "ChatGPT did not complete this app's registration. Start sign-in again."
        case .invalidIdentity: "The ChatGPT account identity could not be verified. No credentials were accepted."
        case .planNotGranted: "The account did not grant access to its ChatGPT plan. Review this app's access in ChatGPT settings."
        case .invalidResponse: "ChatGPT returned an unexpected account response. Try again."
        }
    }
}

public struct ChatGPTAuthorizationAttempt: Sendable {
    public let state: String
    public let nonce: String
    public let verifier: String
    public let challenge: String
    public let redirectURI: URL
    public let hostID: String
    public let clientID: String?
    public let createdAt: Date
    public init(state: String, nonce: String, verifier: String, challenge: String, redirectURI: URL,
                hostID: String, clientID: String? = nil, createdAt: Date = Date()) throws {
        guard redirectURI.scheme == "http", redirectURI.host == "127.0.0.1",
              redirectURI.path == "/auth/callback", let port = redirectURI.port, (1024...65535).contains(port),
              redirectURI.query == nil, redirectURI.fragment == nil, redirectURI.user == nil, redirectURI.password == nil,
              state.count >= 32, nonce.count >= 32, (43...128).contains(verifier.count), challenge.count == 43,
              !hostID.isEmpty, clientID != "dynamic_agent_client" else { throw ChatGPTAuthorizationError.invalidCallback }
        self.state = state; self.nonce = nonce; self.verifier = verifier; self.challenge = challenge
        self.redirectURI = redirectURI; self.hostID = hostID; self.clientID = clientID; self.createdAt = createdAt
    }
    public func authorizationURL(idTokenHint: String? = nil, emailHint: String? = nil) -> URL {
        var components = URLComponents(string: "https://auth.openai.com/api/accounts/authorize")!
        var values = [
            "client_id": clientID ?? "dynamic_agent_client", "ext_agent_host_id": hostID,
            "response_type": "code", "redirect_uri": redirectURI.absoluteString,
            "scope": "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct",
            "resource": "https://api.openai.com/v1", "state": state, "nonce": nonce,
            "code_challenge_method": "S256", "code_challenge": challenge,
        ]
        if clientID == nil { values["agent_name_hint"] = "Personal Assistant" }
        else {
            values["id_token_hint"] = idTokenHint
            values["login_hint"] = emailHint
        }
        components.queryItems = values.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url!
    }
    public func validateCallback(_ url: URL, now: Date = Date()) throws -> ChatGPTAuthorizationCode {
        guard now.timeIntervalSince(createdAt) >= -5, now.timeIntervalSince(createdAt) < 600 else { throw ChatGPTAuthorizationError.expiredAttempt }
        guard url.scheme == redirectURI.scheme, url.host == redirectURI.host, url.port == redirectURI.port,
              url.path == redirectURI.path, url.user == nil, url.password == nil, url.fragment == nil,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              Set(items.map(\.name)).count == items.count else { throw ChatGPTAuthorizationError.invalidCallback }
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        guard let returnedState = values["state"], Self.constantTimeEqual(state, returnedState) else { throw ChatGPTAuthorizationError.invalidCallback }
        if values["error"] != nil { throw ChatGPTAuthorizationError.denied }
        guard let code = values["code"], !code.isEmpty, code.utf8.count <= 4096 else { throw ChatGPTAuthorizationError.invalidCallback }
        let issuedID: String
        if let clientID {
            guard values["client_id"] == nil || values["client_id"] == clientID else { throw ChatGPTAuthorizationError.invalidCallback }
            issuedID = clientID
        } else {
            guard let value = values["client_id"], !value.isEmpty, value != "dynamic_agent_client", value.count <= 256 else {
                throw ChatGPTAuthorizationError.incompleteRegistration
            }
            issuedID = value
        }
        return ChatGPTAuthorizationCode(code: code, clientID: issuedID, redirectURI: redirectURI, verifier: verifier)
    }
    public static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let left = Array(a.utf8), right = Array(b.utf8)
        guard left.count == right.count else { return false }
        var difference: UInt8 = 0
        for index in left.indices { difference |= left[index] ^ right[index] }
        return difference == 0
    }
}

public struct ChatGPTAuthorizationCode: Sendable {
    public var code: String
    public var clientID: String
    public var redirectURI: URL
    public var verifier: String
    public var exchangeForm: Data {
        OAuthForm.encode(["grant_type": "authorization_code", "client_id": clientID, "code": code,
                          "code_verifier": verifier, "redirect_uri": redirectURI.absoluteString,
                          "resource": "https://api.openai.com/v1"])
    }
}
public enum OAuthForm {
    public static func encode(_ fields: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return Data(fields.sorted { $0.key < $1.key }.map {
            $0.key.addingPercentEncoding(withAllowedCharacters: allowed)! + "=" + $0.value.addingPercentEncoding(withAllowedCharacters: allowed)!
        }.joined(separator: "&").utf8)
    }
}

public struct ChatGPTModel: Codable, Identifiable, Equatable, Sendable {
    public var slug: String
    public var displayName: String
    public var visibility: String
    public var id: String { slug }
    enum CodingKeys: String, CodingKey { case slug, displayName = "display_name", visibility }
    public static func catalog(from data: Data) throws -> [Self] {
        struct Response: Decodable { var models: [ChatGPTModel] }
        guard data.count <= 2 * 1024 * 1024 else { throw ChatGPTAuthorizationError.invalidResponse }
        let response = try JSONDecoder().decode(Response.self, from: data)
        var seen = Set<String>()
        return response.models.filter { $0.visibility == "list" && !$0.slug.isEmpty && !$0.displayName.isEmpty && seen.insert($0.slug).inserted }
    }
}

/// Only call after a maintained JWS verifier has checked the signature against OpenAI's JWKS.
public enum ChatGPTIdentityClaims {
    public static func validate(_ claims: JSONValue, clientID: String, nonce: String?, expectedSubject: String? = nil,
                                now: Date = Date()) throws -> (subject: String, email: String?) {
        let audience = claims["aud"]?.stringValue.map { [$0] } ?? claims["aud"]?.arrayValue?.compactMap(\.stringValue) ?? []
        guard claims["iss"]?.stringValue == "https://auth.openai.com", audience.contains(clientID),
              let subject = claims["sub"]?.stringValue, !subject.isEmpty,
              let expiry = claims["exp"]?.numberValue, expiry > now.timeIntervalSince1970 - 5,
              let issued = claims["iat"]?.numberValue, issued <= now.timeIntervalSince1970 + 5,
              expectedSubject == nil || expectedSubject == subject else { throw ChatGPTAuthorizationError.invalidIdentity }
        if let notBefore = claims["nbf"]?.numberValue, notBefore > now.timeIntervalSince1970 + 5 { throw ChatGPTAuthorizationError.invalidIdentity }
        if audience.count > 1, claims["azp"]?.stringValue != clientID { throw ChatGPTAuthorizationError.invalidIdentity }
        if let authorizedParty = claims["azp"]?.stringValue, authorizedParty != clientID { throw ChatGPTAuthorizationError.invalidIdentity }
        if let nonce {
            guard let returned = claims["nonce"]?.stringValue, ChatGPTAuthorizationAttempt.constantTimeEqual(nonce, returned) else {
                throw ChatGPTAuthorizationError.invalidIdentity
            }
        }
        return (subject, claims["email"]?.stringValue)
    }
}
