import AssistantCore
import XCTest
@testable import PersonalAssistant

@MainActor
final class AuditCompletionPlatformTests: XCTestCase {
    func testPresentationTransitionsPreserveEngineConversationAndDraft() async throws {
        let model = AppModel(); try await model.waitUntilReady()
        let original = model.conversation.id; model.draft = "Keep this draft"; model.isRunning = true
        model.present(.savedConversation(UUID(), message: nil))
        XCTAssertEqual(model.conversation.id, original); XCTAssertEqual(model.draft, "Keep this draft"); XCTAssertTrue(model.isRunning)
        model.present(.settings); XCTAssertNil(model.rootPresentation)
        model.didDismissPresentation(); XCTAssertEqual(model.rootPresentation, .settings)
        XCTAssertTrue(model.isRunning); model.isRunning = false
    }
    func testArchiveSelectionRejectsAnUnverifiedLibrary() throws {
        XCTAssertThrowsError(try PrivatePaths.activateData(FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
    }
    func testReadinessDoesNotTurnSavedAuthenticationIntoReadyModelService() async throws {
        let model = AppModel(); try await model.waitUntilReady()
        model.settings.choice = .chatGPT; model.settings.localOnly = true
        XCTAssertEqual(model.selectedAvailability.state, .blocked)
        model.settings.localOnly = false; model.modelCatalog.phase = .unavailable
        XCTAssertNotEqual(model.selectedAvailability.state, .ready)
    }
    func testBoundedReadRejectsOversizedAdvertisedAndActualBodies() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ArchiveHTTPFixture.self]
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        for path in ["advertised", "streamed"] {
            do { _ = try await session.boundedData(for: URLRequest(url: URL(string: "https://fixture.invalid/" + path)!), maximumBytes: 1024); XCTFail("Accepted oversized body") }
            catch { XCTAssertTrue(error.localizedDescription.contains("size limit")) }
        }
        let (bytes, _) = try await session.boundedData(for: URLRequest(url: URL(string: "https://fixture.invalid/small")!), maximumBytes: 1024)
        XCTAssertEqual(bytes, Data("fixture".utf8))
    }
}
private final class ArchiveHTTPFixture: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let advertised = request.url!.lastPathComponent == "advertised", small = request.url!.lastPathComponent == "small"
        let headers = advertised ? ["Content-Length": "99999999"] : [:]
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: small ? Data("fixture".utf8) : Data(repeating: 65, count: 4096))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
