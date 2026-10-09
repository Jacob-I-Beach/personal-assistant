import Foundation
import XCTest
@testable import AssistantCore

final class AuthorizationTests: XCTestCase {
    private func attempt(clientID: String? = nil) throws -> ChatGPTAuthorizationAttempt {
        try ChatGPTAuthorizationAttempt(state: String(repeating: "s", count: 43), nonce: String(repeating: "n", count: 43),
            verifier: String(repeating: "v", count: 64), challenge: String(repeating: "c", count: 43),
            redirectURI: URL(string: "http://127.0.0.1:54321/auth/callback")!, hostID: "urn:uuid:fixture", clientID: clientID)
    }
    func testRegistrationCallbackBindsStateClientAndExactLoopbackURI() throws {
        let pending = try attempt()
        let base = pending.redirectURI.absoluteString + "?state=" + pending.state
        let code = try pending.validateCallback(URL(string: base + "&code=fixture-code&client_id=oaiapp_fixture")!)
        XCTAssertEqual(code.clientID, "oaiapp_fixture")
        let form = String(decoding: code.exchangeForm, as: UTF8.self)
        XCTAssertTrue(form.contains("client_id=oaiapp_fixture"))
        XCTAssertFalse(form.contains("dynamic_agent_client"))
        for url in [base + "&code=x", base + "&code=x&client_id=dynamic_agent_client",
                    base + "&state=duplicate&code=x&client_id=oaiapp_fixture",
                    base.replacingOccurrences(of: "54321", with: "54322") + "&code=x&client_id=oaiapp_fixture",
                    base.replacingOccurrences(of: "127.0.0.1", with: "localhost") + "&code=x&client_id=oaiapp_fixture"] {
            XCTAssertThrowsError(try pending.validateCallback(URL(string: url)!))
        }
        XCTAssertThrowsError(try pending.validateCallback(URL(string: base + "&code=x&client_id=oaiapp_fixture")!, now: pending.createdAt.addingTimeInterval(601)))
    }
    func testReturningAccountCannotReplaceRegistrationAndDenialIsVerified() throws {
        let pending = try attempt(clientID: "oaiapp_original")
        let base = pending.redirectURI.absoluteString + "?state=" + pending.state
        XCTAssertEqual(try pending.validateCallback(URL(string: base + "&code=x")!).clientID, "oaiapp_original")
        XCTAssertThrowsError(try pending.validateCallback(URL(string: base + "&code=x&client_id=oaiapp_other")!))
        XCTAssertThrowsError(try pending.validateCallback(URL(string: base + "&error=access_denied")!)) { XCTAssertEqual($0 as? ChatGPTAuthorizationError, .denied) }
        XCTAssertThrowsError(try pending.validateCallback(URL(string: pending.redirectURI.absoluteString + "?state=bad&error=access_denied")!)) { XCTAssertEqual($0 as? ChatGPTAuthorizationError, .invalidCallback) }
        let url = pending.authorizationURL(idTokenHint: "fixture", emailHint: "example@example.invalid").absoluteString
        XCTAssertFalse(url.contains("agent_name_hint"))
        XCTAssertTrue(url.contains("id_token_hint"))
    }
    func testIdentityClaimsRejectCrossAccountIssuerAudienceNonceAndExpiry() throws {
        let now = Date()
        let good: [String: JSONValue] = ["iss": .string("https://auth.openai.com"), "sub": .string("subject"),
            "aud": .string("oaiapp_test"), "nonce": .string("nonce"), "iat": .number(now.timeIntervalSince1970), "exp": .number(now.timeIntervalSince1970 + 60)]
        XCTAssertEqual(try ChatGPTIdentityClaims.validate(.object(good), clientID: "oaiapp_test", nonce: "nonce", now: now).subject, "subject")
        for (field, value) in ["iss": JSONValue.string("https://example.invalid"), "aud": .string("other"), "nonce": .string("other"), "exp": .number(1)] {
            var bad = good; bad[field] = value
            XCTAssertThrowsError(try ChatGPTIdentityClaims.validate(.object(bad), clientID: "oaiapp_test", nonce: "nonce", now: now))
        }
        XCTAssertThrowsError(try ChatGPTIdentityClaims.validate(.object(good), clientID: "oaiapp_test", nonce: "nonce", expectedSubject: "other"))
    }
    func testCatalogUsesAccountOrderingAndFiltersHiddenModels() throws {
        let data = Data(#"{"models":[{"slug":"b","display_name":"Second alphabetically","visibility":"list"},{"slug":"hidden","visibility":"hidden"},{"slug":"a","display_name":"First alphabetically","visibility":"list"}]}"#.utf8)
        XCTAssertEqual(try ChatGPTModel.catalog(from: data).map(\.id), ["b", "a"])
    }
    func testAccountRouteUsesNamespacedToolsAndRefusesOtherServers() throws {
        let backend = try NetworkModelBackend(baseURL: URL(string: "https://api.openai.com/v1")!, model: "fixture-model", wireProtocol: .responses, chatGPTAccountID: "fixture-account")
        let request = try backend.makeRequest(ModelRequest(instructions: "fixture", messages: [], tools: [CaptureToolBroker.definition]))
        let body = try JSONDecoder().decode(JSONValue.self, from: request.httpBody!)
        XCTAssertEqual(body["tools"]?.arrayValue?.first?["type"]?.stringValue, "namespace")
        XCTAssertEqual(body["store"], .bool(false))
        XCTAssertEqual(body["stream"], .bool(true))
        XCTAssertNil(body["previous_response_id"])
        XCTAssertThrowsError(try NetworkModelBackend(baseURL: URL(string: "https://example.invalid/v1")!, model: "fixture", wireProtocol: .responses, chatGPTAccountID: "fixture"))
    }
}
