import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import AssistantCore

final class CoherenceTests: XCTestCase, @unchecked Sendable {
    func testMillionTokenSelectionUsesSupportedModelAndReservesOutput() {
        let large = ModelContextBudget(model: "gpt-6.1-sol", requestedInputTokens: 1_000_000)
        XCTAssertEqual(large.selectedInputTokens, 1_000_000)
        XCTAssertLessThanOrEqual(large.selectedInputTokens + large.outputReserve, large.modelWindow)
        XCTAssertTrue(large.limitSource.contains("Published"))
        let account = ModelContextBudget(model: "gpt-6.1-sol", advertisedMaximumWindow: 200_000, requestedInputTokens: 1_000_000)
        XCTAssertEqual(account.modelWindow, 200_000)
        XCTAssertEqual(account.selectedInputTokens, 183_616)
        XCTAssertFalse(account.presets.contains(1_000_000))
    }
    func testUnknownModelsAndInvalidCatalogLimitsRemainConservative() {
        for invalid in [Int.min, -1, 0, 1024, Int.max] {
            let plan = ModelContextBudget(model: "unverified-custom-model", advertisedWindow: invalid, requestedInputTokens: Int.max)
            XCTAssertEqual(plan.maximumInputTokens, 24_576)
            XCTAssertEqual(plan.selectedInputTokens, 24_576)
            XCTAssertEqual(plan.limitSource, "Conservative default")
        }
    }
    func testCatalogContextOverridesDocumentationWithoutGrantingCapabilities() throws {
        let values = try ChatGPTModel.catalog(from: Data(#"{"models":[{"slug":"gpt-6.1-sol","display_name":"Example","visibility":"list","context_window":160000},{"slug":"custom","display_name":"Custom","visibility":"list","context_window":"1000000"}]}"#.utf8))
        XCTAssertEqual(values[0].contextWindow, 160_000); XCTAssertNil(values[1].contextWindow)
    }
    func testContextPreferenceActuallyChangesSelectedHistoryButNotSavedInput() throws {
        let messages = (0..<180).flatMap { index in [Message(role: .user, text: "Question \(index)"), Message(role: .assistant, text: String(repeating: "word ", count: 500))] }
        let small = try ContextPlanner.select(messages, instructions: "Instructions", tools: [], limits: .init(maximumTextBytes: ModelContextBudget(model: "gpt-6.1-sol", requestedInputTokens: 32_000).textByteBudget))
        let large = try ContextPlanner.select(messages, instructions: "Instructions", tools: [], limits: .init(maximumTextBytes: ModelContextBudget(model: "gpt-6.1-sol", requestedInputTokens: 1_000_000).textByteBudget))
        XCTAssertGreaterThan(large.messages.count, small.messages.count)
        XCTAssertEqual(large.messages, messages)
        XCTAssertEqual(small.messages.last, messages.last)
    }
    func testOutputReserveIsAppliedToTheActualResponsesRequest() throws {
        let plan = ModelContextBudget(model: "gpt-6.1-sol", requestedInputTokens: 1_000_000)
        let backend = try NetworkModelBackend(baseURL: URL(string: "https://api.openai.com/v1")!, model: "gpt-6.1-sol", wireProtocol: .responses, contextBudget: plan)
        let request = try backend.makeRequest(.init(instructions: "Test", messages: [], tools: []))
        let body = try JSONDecoder().decode(JSONValue.self, from: XCTUnwrap(request.httpBody))
        XCTAssertEqual(body["max_output_tokens"], .number(50_000))
        XCTAssertEqual(backend.contextLimits.maximumTextBytes, plan.textByteBudget)
        let account = try NetworkModelBackend(baseURL: URL(string: "https://api.openai.com/v1")!, model: "gpt-6.1-sol", wireProtocol: .responses,
                                              credential: "synthetic-token", chatGPTAccountID: "synthetic-account", contextBudget: plan)
        let accountRequest = try account.makeRequest(.init(instructions: "Test", messages: [], tools: []))
        let accountBody = try JSONDecoder().decode(JSONValue.self, from: XCTUnwrap(accountRequest.httpBody))
        XCTAssertNil(accountBody["max_output_tokens"])
        XCTAssertNil(accountBody["background"])
        XCTAssertEqual(accountBody["stream"], .bool(true))
        XCTAssertEqual(accountBody["store"], .bool(false))
    }
    func testExplicitSendDoesNotSilentlyApproveHealthOrRevokedSharing() throws {
        var conversation = Conversation()
        XCTAssertFalse(ConversationSharing.needsReview(conversation, destination: "chosen", includesHealth: false, confirmNewChats: false))
        XCTAssertTrue(ConversationSharing.needsReview(conversation, destination: "chosen", includesHealth: true, confirmNewChats: false))
        conversation.requiresNetworkReview = true
        XCTAssertTrue(ConversationSharing.needsReview(conversation, destination: "chosen", includesHealth: false, confirmNewChats: false))
        conversation.allowedNetworkDestinations.insert("chosen")
        XCTAssertFalse(ConversationSharing.needsReview(conversation, destination: "chosen", includesHealth: false, confirmNewChats: true))
        XCTAssertTrue(ConversationSharing.needsReview(conversation, destination: "another-account", includesHealth: false, confirmNewChats: false))
        let decoded = try JSONDecoder().decode(Conversation.self, from: JSONEncoder().encode(conversation))
        XCTAssertTrue(decoded.requiresNetworkReview)
    }
    func testAppOrientationIsBoundedAndDistinguishesUnavailableAccess() {
        let state = AssistantAppContext(planningConnected: true, planningSharedWithModel: false, healthAvailable: false)
        XCTAssertLessThan(state.instructions.utf8.count, 3_300)
        XCTAssertTrue(state.instructions.contains("connected-model planning sharing: off"))
        XCTAssertTrue(state.instructions.contains("requires a capability-provisioned installation"))
        XCTAssertTrue(state.instructions.contains("iOS processing time"))
        XCTAssertTrue(AssistantAppContext(computerEnabled: true).instructions.contains("owns accepted ChatGPT tasks from Send"))
    }
    func testReceiptProseIsRecognizedAndInternalFieldsStayOutOfReadableResult() {
        let nodes = ReceiptDetails.nodes(.object(["text": .string("## A useful answer\n\n**Selected evidence**"), "role": .string("assistant"), "total_characters": .number(8_532), "completed_at": .string("2026-10-11T00:00:00Z")]))
        XCTAssertEqual(nodes.count, 1); XCTAssertTrue(nodes[0].isProse)
        XCTAssertEqual(nodes[0].title, "Saved text")
    }
    func testHealthAvailabilityRequiresTheEmbeddedProfileCapability() throws {
        let granted = try PropertyListSerialization.data(fromPropertyList: ["Entitlements": ["com.apple.developer.healthkit": true]], format: .xml, options: 0)
        let denied = try PropertyListSerialization.data(fromPropertyList: ["Entitlements": ["com.apple.developer.healthkit": false]], format: .xml, options: 0)
        var wrapped = Data([0x30, 0x80, 0x01]); wrapped.append(granted); wrapped.append(contentsOf: [0, 0])
        XCTAssertTrue(ProvisionedCapabilities.healthKit(in: wrapped))
        XCTAssertFalse(ProvisionedCapabilities.healthKit(in: denied))
        XCTAssertFalse(ProvisionedCapabilities.healthKit(in: Data("<plist>broken".utf8)))
        XCTAssertFalse(ProvisionedCapabilities.healthKit(in: Data(repeating: 0, count: 2 * 1024 * 1024 + 1)))
    }
    func testSingleSavedResultReadsDirectlyButUnknownOutcomesKeepTheirState() {
        let content: JSONValue = .array([.object(["title": .string("Earlier decision"), "text": .string("**Use the selected folder.**")])])
        let complete: JSONValue = .object(["status": .string("completed"), "tool_succeeded": .bool(true), "result": content])
        XCTAssertTrue(ReceiptDetails.readableContent(complete).contains { $0.title == "Saved text" && $0.isProse })
        let uncertain: JSONValue = .object(["status": .string("outcome_unknown"), "result": content])
        XCTAssertTrue(ReceiptDetails.readableContent(uncertain).contains { $0.title == "Status" && $0.value?.contains("not confirmed") == true })
    }
    func testContextFailureNeedsAnActualBudgetIncreaseBeforeManualRetry() {
        let id = UUID()
        var work = WorkTurn(id: id, conversationID: UUID(), userMessageID: id, backendID: "synthetic", destination: "fixture", goal: "Continue", configuration: .object(["context_text_bytes": .number(128_000)]))
        work.needsChangedRequest = true
        XCTAssertFalse(work.permitsContextRetry(maximumTextBytes: 128_000))
        XCTAssertFalse(work.permitsContextRetry(maximumTextBytes: 64_000))
        XCTAssertTrue(work.permitsContextRetry(maximumTextBytes: 384_000))
        XCTAssertEqual(ModelContextBudget(model: "gpt-6.1-sol").outputReserve, 128_000)
    }
    func testNetworkActivityReportsRealProgressBeforeAnyAnswerText() async throws {
        let chunks = [Data("event: response.created\ndata: {\"type\":\"response.created\"}\n\n".utf8),
            Data("event: response.output_text.delta\ndata: {\"type\":\"response.output_text.delta\",\"item_id\":\"answer\",\"output_index\":0,\"content_index\":0,\"delta\":\"Done\"}\n\n".utf8),
            Data("event: response.completed\ndata: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\",\"output\":[]}}\n\n".utf8)]
        let backend = try NetworkModelBackend(baseURL: URL(string: "http://127.0.0.1:9800/v1")!, model: "synthetic", wireProtocol: .responses, transport: ProgressTransport(chunks: chunks))
        var received = 0, text = "", completed = false, progressBeforeText = false
        for try await event in backend.stream(.init(instructions: "Synthetic", messages: [], tools: [])) {
            switch event {
            case .transportProgress(let bytes): received += bytes; if text.isEmpty { progressBeforeText = true }
            case .textDelta(let value): text += value
            case .completed: completed = true
            default: break
            }
        }
        XCTAssertEqual(received, chunks.reduce(0) { $0 + $1.count })
        XCTAssertTrue(progressBeforeText); XCTAssertTrue(completed)
    }
}

private struct ProgressTransport: HTTPStreamingTransport {
    let chunks: [Data]
    func stream(_ request: URLRequest) -> AsyncThrowingStream<Data, any Error> {
        AsyncThrowingStream { output in for chunk in chunks { output.yield(chunk) }; output.finish() }
    }
}
