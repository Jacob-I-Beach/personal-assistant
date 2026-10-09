import AssistantCore
import Foundation
import JOSESwift
import Security
import UIKit
import XCTest
@testable import PersonalAssistant

@MainActor
final class AuthorizationPlatformTests: XCTestCase {
    func testUnprovisionedHealthBuildRejectsBeforeAuthorization() async {
        XCTAssertFalse(HealthOverviewService.isEnabledInThisBuild)
        let service = HealthOverviewService()
        XCTAssertFalse(service.isAvailable)
        do {
            try await service.requestAccess()
            XCTFail("The unprovisioned build must not ask for Health access.")
        } catch { XCTAssertTrue(error.localizedDescription.contains("HealthKit capability")) }
        do {
            _ = try await service.overview()
            XCTFail("The unprovisioned build must not query Health.")
        } catch { XCTAssertTrue(error.localizedDescription.contains("HealthKit capability")) }
    }
    func testBundledModelCatalogHasRealSizesAndWeightDigests() throws {
        XCTAssertNotNil(UIImage(named: "AssistantMark"))
        let entries = try LocalModelCatalogEntry.bundled()
        XCTAssertEqual(entries.count, 3)
        for entry in entries {
            XCTAssertGreaterThan(entry.downloadBytes, 1_000_000_000)
            XCTAssertEqual(entry.downloadBytes, entry.files.reduce(0) { $0 + $1.bytes })
            let weights = entry.files.filter { $0.name.hasSuffix(".safetensors") }
            XCTAssertFalse(weights.isEmpty)
            XCTAssertTrue(weights.allSatisfy { $0.bytes > 0 && $0.sha256?.count == 64 })
        }
    }
    func testLoopbackCallbackAcceptsValidStateAndRejectsBadState() async throws {
        let receiver = AccountCallbackReceiver()
        let redirect = try await receiver.start()
        defer { receiver.stop() }
        let attempt = try ChatGPTAuthorizationAttempt(state: String(repeating: "s", count: 43), nonce: String(repeating: "n", count: 43),
            verifier: String(repeating: "v", count: 64), challenge: String(repeating: "c", count: 43), redirectURI: redirect, hostID: "urn:uuid:synthetic")
        receiver.prepare(attempt)
        let bad = URL(string: redirect.absoluteString + "?state=bad&code=fixture&client_id=oaiapp_fixture")!
        let (_, badResponse) = try await URLSession.shared.data(from: bad)
        XCTAssertEqual((badResponse as? HTTPURLResponse)?.statusCode, 400)
        let good = URL(string: redirect.absoluteString + "?state=" + attempt.state + "&code=fixture&client_id=oaiapp_fixture")!
        let (_, goodResponse) = try await URLSession.shared.data(from: good)
        XCTAssertEqual((goodResponse as? HTTPURLResponse)?.statusCode, 200)
        let received = try await receiver.callback()
        XCTAssertEqual(received.code, "fixture")
        XCTAssertEqual(received.clientID, "oaiapp_fixture")
    }

    func testSignatureValidationRejectsTamperingWrongKeyAndNonce() throws {
        let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits as String: 2048]
        let privateKey = try XCTUnwrap(SecKeyCreateRandomKey(attributes as CFDictionary, nil))
        let publicKey = try XCTUnwrap(SecKeyCopyPublicKey(privateKey))
        let jwk = try RSAPublicKey(publicKey: publicKey, additionalParameters: ["kid": "fixture", "alg": "RS256", "use": "sig"])
        let key = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(jwk))
        let keys = JSONValue.object(["keys": .array([key])])
        let claims = JSONValue.object(["iss": .string("https://auth.openai.com"), "sub": .string("fixture-subject"),
            "aud": .string("oaiapp_fixture"), "nonce": .string("fixture-nonce"),
            "iat": .number(Date().timeIntervalSince1970), "exp": .number(Date().addingTimeInterval(120).timeIntervalSince1970)])
        var header = JWSHeader(algorithm: .RS256); header.kid = "fixture"
        let signer = try XCTUnwrap(Signer(signatureAlgorithm: .RS256, key: privateKey))
        let signed = try JWS(header: header, payload: Payload(JSONEncoder().encode(claims)), signer: signer).compactSerializedString
        XCTAssertEqual(try OpenAIIDTokenVerifier.verify(signed, jwks: keys, clientID: "oaiapp_fixture", nonce: "fixture-nonce").subject, "fixture-subject")
        XCTAssertThrowsError(try OpenAIIDTokenVerifier.verify(signed, jwks: keys, clientID: "oaiapp_fixture", nonce: "wrong"))
        XCTAssertThrowsError(try OpenAIIDTokenVerifier.verify(signed, jwks: .object(["keys": .array([])]), clientID: "oaiapp_fixture", nonce: "fixture-nonce"))
        var pieces = signed.split(separator: ".").map(String.init)
        pieces[1] = Data("{\"sub\":\"forged\"}".utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
        XCTAssertThrowsError(try OpenAIIDTokenVerifier.verify(pieces.joined(separator: "."), jwks: keys, clientID: "oaiapp_fixture", nonce: "fixture-nonce"))
    }
}
