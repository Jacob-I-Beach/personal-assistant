import XCTest
@testable import AssistantCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

func makeTestStore() throws -> LocalStore {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build/test-data/" + UUID().uuidString)
    return try LocalStore(root: root)
}
func testCapture(id: UUID = UUID()) -> CaptureObservation {
    CaptureObservation(id: id, source: "synthetic-test", imageWidth: 100, imageHeight: 100,
                       recognizedText: ["MODEL ABC-123"],
                       depth: DepthGrid(width: 1, height: 1, meters: [1.5], confidence: [2]))
}

final class CoreTests: XCTestCase, @unchecked Sendable {
    func testSSEPreservesUTF8AcrossEveryByteBoundaryAndMultilineData() throws {
        let source = ": comment\r\nevent: text\r\ndata: héllo 🌎\r\ndata: second line\r\n\r\ndata: [DONE]\n\n"
        var decoder = SSEDecoder()
        var events: [ServerSentEvent] = []
        for byte in source.utf8 { events += try decoder.append(Data([byte])) }
        XCTAssertEqual(events, [ServerSentEvent(event: "text", data: "héllo 🌎\nsecond line"), ServerSentEvent(event: nil, data: "[DONE]")])
        XCTAssertFalse(decoder.hasUnterminatedEvent)
    }

    func testSSERejectsOversizedUnterminatedData() throws {
        var decoder = SSEDecoder(maximumEventBytes: 20)
        XCTAssertThrowsError(try decoder.append(Data(repeating: 65, count: 21)))
    }

    func testDepthRejectsInvalidShapeAndMasksLowConfidence() throws {
        XCTAssertThrowsError(try DepthGrid(width: 2, height: 2, meters: [1]).validate())
        var readings: [Float?] = Array(repeating: 5, count: 100)
        var quality: [UInt8] = Array(repeating: 2, count: 100)
        readings[44] = 1; readings[45] = 100; readings[54] = 3; readings[55] = 4
        quality[45] = 0
        let summary = try DepthGrid(width: 10, height: 10, meters: readings, confidence: quality).centerSummary()
        XCTAssertEqual(summary.medianMeters, 3)
        XCTAssertEqual(summary.acceptedSamples, 3)
        XCTAssertEqual(summary.rejectedSamples, 1)
        XCTAssertNil(try DepthGrid(width: 1, height: 1, meters: [1], confidence: [0]).centerSummary().medianMeters)
        XCTAssertThrowsError(try DepthGrid(width: 1, height: 1, meters: [.nan]).validate())
    }

    func testPersistenceSurvivesNewStoreAndMarksPartialResponseInterrupted() async throws {
        let store = try makeTestStore()
        var c = Conversation(title: "Survives restart")
        c.messages = [Message(role: .user, text: "Keep this"), Message(role: .assistant, text: "Partial", state: .streaming)]
        try await store.save(c)
        let reopened = try LocalStore(root: store.root)
        let loaded = try await reopened.loadConversation(c.id)
        XCTAssertEqual(loaded.messages.map(\.text), ["Keep this", "Partial"])
        XCTAssertEqual(loaded.messages.last?.state, .interrupted)
    }

    func testUnknownSchemaIsNotOverwritten() async throws {
        let store = try makeTestStore()
        var c = Conversation(); c.schemaVersion = 99
        do { try await store.save(c); XCTFail("Must reject unknown schema") }
        catch AssistantError.unsupportedSchema(99) { }
    }

    func testToolCanOnlyReadExplicitlyAttachedCaptureAndRejectsAdditionalArguments() async throws {
        let store = try makeTestStore()
        let capture = testCapture()
        try await store.saveCapture(capture, jpeg: Data([0xff, 0xd8, 0xff, 0xd9]))
        let call = ToolCall(id: "test", name: "read_capture", arguments: .object(["capture_id": .string(capture.id.uuidString)]))
        let denied = await CaptureToolBroker(store: store, allowedCaptureIDs: []).execute(call)
        XCTAssertFalse(denied.succeeded)
        let broker = CaptureToolBroker(store: store, allowedCaptureIDs: [capture.id])
        let result = await broker.execute(call)
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.output["center_depth"]?["medianMeters"]?.numberValue, 1.5)
        var injected = call
        injected.arguments = .object(["capture_id": .string(capture.id.uuidString), "path": .string("../../secret")])
        let invalid = await broker.execute(injected)
        XCTAssertFalse(invalid.succeeded)
    }

    func testEndpointPolicyRejectsCredentialURLsPublicHTTPAndFakePrivateHostnames() throws {
        for text in ["http://example.com/v1", "https://user:secret@example.com/v1", "http://10.evil.0.0.1/v1", "https://example.com/v1?key=secret"] {
            XCTAssertThrowsError(try EndpointPolicy.validate(URL(string: text)!))
        }
        for text in ["https://api.openai.com/v1", "http://192.168.1.10:1234/v1", "http://127.0.0.1:1234/v1"] {
            XCTAssertNoThrow(try EndpointPolicy.validate(URL(string: text)!))
        }
    }

    func testChatToolCallIsNotReleasedBeforeDone() throws {
        var decoder = ModelWireDecoder(wireProtocol: .chatCompletions)
        let first = try decoder.consume(ServerSentEvent(event: nil, data: #"{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call1","function":{"name":"read_capture","arguments":"{\"capture_id\":"}}]}}]}"#))
        XCTAssertTrue(first.isEmpty)
        let next = try decoder.consume(ServerSentEvent(event: nil, data: #"{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"abc\"}"}}]},"finish_reason":"tool_calls"}]}"#))
        XCTAssertTrue(next.isEmpty)
        let final = try decoder.consume(ServerSentEvent(event: nil, data: "[DONE]"))
        XCTAssertTrue(decoder.completed)
        guard case .toolCall(let call) = final.first else { return XCTFail("Expected completed tool call") }
        XCTAssertEqual(call.arguments["capture_id"]?.stringValue, "abc")
    }

    func testTruncatedChatCompletionIsAnError() throws {
        var decoder = ModelWireDecoder(wireProtocol: .chatCompletions)
        _ = try decoder.consume(ServerSentEvent(event: nil, data: #"{"choices":[{"delta":{"content":"partial"},"finish_reason":"length"}]}"#))
        XCTAssertThrowsError(try decoder.consume(ServerSentEvent(event: nil, data: "[DONE]")))
        XCTAssertFalse(decoder.completed)
    }

    func testResponsesFailureDoesNotReleasePreviouslyFinishedToolItem() throws {
        var decoder = ModelWireDecoder(wireProtocol: .responses)
        let item = try decoder.consume(ServerSentEvent(event: nil, data: #"{"type":"response.output_item.done","output_index":0,"item":{"type":"function_call","call_id":"one","name":"read_capture","arguments":"{}"}}"#))
        XCTAssertTrue(item.isEmpty)
        XCTAssertThrowsError(try decoder.consume(ServerSentEvent(event: nil, data: #"{"type":"response.failed","response":{"error":{"message":"quota exhausted"}}}"#)))
        XCTAssertFalse(decoder.completed)
    }

    func testNetworkPayloadHasExplicitLocalToolAndNoProviderStorage() throws {
        let backend = try NetworkModelBackend(baseURL: URL(string: "https://api.openai.com/v1")!, model: "chosen-model", wireProtocol: .responses)
        let input = ModelRequest(instructions: "Instructions", messages: [ModelInputMessage(message: Message(role: .user, text: "Hello"))], tools: [CaptureToolBroker.definition])
        let request = try backend.makeRequest(input)
        let body = try JSONDecoder().decode(JSONValue.self, from: request.httpBody!)
        XCTAssertEqual(body["store"], .bool(false))
        XCTAssertEqual(body["tools"]?.arrayValue?.first?["name"]?.stringValue, "read_capture")
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")
    }

    func testModelSwitchDoesNotReplayAnotherProvidersOpaqueContinuation() throws {
        var message = Message(role: .assistant, text: "Keep the useful answer")
        message.continuation = ProviderContinuation(providerID: "another-model", items: [.object(["secret_opaque_item": .string("old")])])
        let backend = try NetworkModelBackend(baseURL: URL(string: "https://api.openai.com/v1")!, model: "new-model", wireProtocol: .responses)
        let request = try backend.makeRequest(ModelRequest(instructions: "", messages: [ModelInputMessage(message: message)], tools: []))
        let body = String(decoding: request.httpBody!, as: UTF8.self)
        XCTAssertTrue(body.contains("Keep the useful answer"))
        XCTAssertFalse(body.contains("secret_opaque_item"))
    }
}
