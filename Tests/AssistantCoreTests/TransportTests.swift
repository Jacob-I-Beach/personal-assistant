import XCTest
@testable import AssistantCore
import Foundation

final class TransportTests: XCTestCase, @unchecked Sendable {
    private func backend(path: String = "/v1", format: NetworkProtocol = .responses) throws -> NetworkModelBackend {
        guard let base = ProcessInfo.processInfo.environment["ASSISTANT_FIXTURE_BASE_URL"] else {
            throw XCTSkip("Run scripts/Test-Core.ps1 -Integration to include loopback transport tests.")
        }
        return try NetworkModelBackend(baseURL: URL(string: base + path)!, model: "synthetic-fixture", wireProtocol: format)
    }
    private var request: ModelRequest {
        ModelRequest(instructions: "Test only", messages: [ModelInputMessage(message: Message(role: .user, text: "Hello"))], tools: [])
    }
    func testRealURLSessionResponsesStreaming() async throws {
        let provider = try backend()
        var result = "", complete = false
        for try await event in provider.stream(request) {
            if case .responseContent(let parts) = event { result = ResponsePresentation.text(in: parts) }
            if case .completed = event { complete = true }
        }
        XCTAssertEqual(result, "Hello 🌎")
        XCTAssertTrue(complete)
    }
    func testRealURLSessionChatCompletionsStreaming() async throws {
        let provider = try backend(format: .chatCompletions)
        var result = ""
        for try await event in provider.stream(request) { if case .textDelta(let text) = event { result += text } }
        XCTAssertEqual(result, "Hello 🌎")
    }
    func testConnectionEndingEarlyIsNotSuccess() async throws {
        let provider = try backend(path: "/cut/v1")
        do { for try await _ in provider.stream(request) {}; XCTFail("Expected incomplete stream") }
        catch AssistantError.incompleteResponse { }
    }
    func testProviderFailureAfterPartialResponseIsNotSuccess() async throws {
        let provider = try backend(path: "/failed/v1")
        do { for try await _ in provider.stream(request) {}; XCTFail("Expected provider error") }
        catch AssistantError.provider(let message) { XCTAssertTrue(message.contains("Synthetic failure")) }
    }
    func testRedirectDoesNotForwardPrivateRequest() async throws {
        let provider = try backend(path: "/redirect/v1")
        do { for try await _ in provider.stream(request) {}; XCTFail("Redirect must be rejected") }
        catch AssistantError.provider(let message) { XCTAssertTrue(message.contains("307")) }
    }
    func testHTTP401IsReportedWithoutParsingHTMLAsModelOutput() async throws {
        let provider = try backend(path: "/unauthorized/v1")
        do { for try await _ in provider.stream(request) {}; XCTFail("Expected HTTP error") }
        catch AssistantError.provider(let message) { XCTAssertTrue(message.contains("401")) }
    }
    func testFullHTTPToolLoopUsesTheSavedCapture() async throws {
        for path in ["/tool/v1", "/tool-empty/v1"] {
        let provider = try backend(path: path)
        let store = try makeTestStore(), capture = testCapture()
        try await store.saveCapture(capture, jpeg: Data([1, 2, 3]))
        var conversation = Conversation()
        conversation.allowedNetworkDestinations.insert(provider.networkDestination!)
        for try await _ in AssistantEngine(store: store).respond(conversation: conversation, text: "Inspect", captureIDs: [capture.id], backend: provider) { }
        let result = try await store.loadConversation(conversation.id)
        XCTAssertEqual(result.messages.map(\.role), [.user, .assistant, .tool, .assistant])
        XCTAssertEqual(result.messages.last?.text, "Verified saved capture.")
        }
    }
    func testEmptyHTTPCompletionPersistsAVisibleFailureReason() async throws {
        let provider = try backend(path: "/empty/v1"), store = try makeTestStore()
        var conversation = Conversation(); conversation.allowedNetworkDestinations.insert(provider.networkDestination!)
        do {
            for try await _ in AssistantEngine(store: store).respond(conversation: conversation, text: "Inspect", captureIDs: [], backend: provider) { }
            XCTFail("Empty response was presented as success")
        } catch { XCTAssertTrue(error.localizedDescription.contains("without an answer")) }
        let saved = try await store.loadConversation(conversation.id)
        XCTAssertEqual(saved.messages.last?.state, .failed)
        XCTAssertTrue(saved.messages.last?.failureReason?.contains("without an answer") == true)
    }
}
