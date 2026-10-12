import AssistantCore
import Foundation
import XCTest
@testable import PersonalAssistant

@MainActor
final class CompanionTLSPlatformTests: XCTestCase {
    private func fixture(_ path: String) async throws -> JSONValue {
        guard ProcessInfo.processInfo.environment["ASSISTANT_TLS_FIXTURE"] == "1" else {
            throw XCTSkip("Run the companion-tls workflow scope to start the synthetic TLS server.")
        }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.connectionProxyDictionary = [:]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let (data, _) = try await session.data(from: URL(string: "http://localhost:48682" + path)!)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    private func client(host: String = "100.64.0.1", wrongPin: Bool = false) async throws -> CompanionClient {
        let config = try await fixture("/config")
        let fingerprint = try XCTUnwrap(config["fingerprint"]?.stringValue)
        return try CompanionClient(baseURL: URL(string: "https://\(host):48683")!,
                                   fingerprint: wrongPin ? String(repeating: "0", count: 64) : fingerprint,
                                   token: "synthetic-device-token")
    }

    func testLegacyPolicyRejectsTailscaleCertificate() async throws {
        let ats = Bundle.main.object(forInfoDictionaryKey: "NSAppTransportSecurity") as? [String: Any]
        guard ats?["NSExceptionDomains"] == nil else { throw XCTSkip("The legacy-policy probe runs before restoring the repaired app plist.") }
        let connection = try await client()
        defer { connection.session.invalidateAndCancel() }
        do {
            _ = try await connection.json("/v1/legacy-probe")
            XCTFail("The legacy policy unexpectedly succeeded; do not attribute this report to ATS without more evidence.")
        } catch {
            let error = error as NSError
            print("Legacy Tailscale TLS result: \(error.domain) \(error.code)")
            XCTAssertEqual(error.domain, NSURLErrorDomain)
            XCTAssertEqual(error.code, URLError.secureConnectionFailed.rawValue)
        }
    }

    func testPinnedCertificateConnectsThroughTailscaleAddress() async throws {
        let connection = try await client()
        defer { connection.session.invalidateAndCancel() }
        let result = try await connection.json("/v1/accepted-pin")
        XCTAssertEqual(result["status"], .string("ok"))
        let observations = try await fixture("/observations")
        XCTAssertTrue(observations["requests"]?.arrayValue?.contains { $0["path"] == .string("/v1/accepted-pin") && $0["authorized"] == .bool(true) } == true)
    }

    func testExistingLocalConnectionStillWorks() async throws {
        let connection = try await client(host: "127.0.0.1")
        defer { connection.session.invalidateAndCancel() }
        let result = try await connection.json("/v1/local")
        XCTAssertEqual(result["status"], .string("ok"))
    }

    func testWrongCertificateCannotReceiveDeviceCredential() async throws {
        let connection = try await client(wrongPin: true)
        defer { connection.session.invalidateAndCancel() }
        do {
            _ = try await connection.json("/v1/rejected-pin")
            XCTFail("A different certificate must never receive a request or device token.")
        } catch {
            XCTAssertEqual((error as NSError).domain, NSURLErrorDomain)
        }
        let observations = try await fixture("/observations")
        XCTAssertFalse(observations["requests"]?.arrayValue?.contains { $0["path"] == .string("/v1/rejected-pin") } == true)
    }

    func testRedirectCannotForwardDeviceCredential() async throws {
        let connection = try await client()
        defer { connection.session.invalidateAndCancel() }
        do {
            _ = try await connection.json("/v1/redirect")
            XCTFail("The companion must refuse every redirect.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("302"))
        }
        let observations = try await fixture("/observations")
        XCTAssertFalse(observations["requests"]?.arrayValue?.contains { $0["path"] == .string("/credential-sink") } == true)
    }

    func testCompanionStillRequiresHTTPSAndDoesNotOptOutGlobally() {
        XCTAssertThrowsError(try CompanionClient(baseURL: URL(string: "http://100.64.0.1:48683")!, fingerprint: String(repeating: "0", count: 64), token: ""))
        let ats = Bundle.main.object(forInfoDictionaryKey: "NSAppTransportSecurity") as? [String: Any]
        XCTAssertNotEqual(ats?["NSAllowsArbitraryLoads"] as? Bool, true)
        XCTAssertEqual(Set((ats?["NSExceptionDomains"] as? [String: Any])?.keys.map { $0 } ?? []), ["100.64.0.0/10"])
    }
}
