import XCTest
@testable import AssistantCore
import Foundation

actor ScriptedTurns {
    var turns: [[ModelEvent]]
    var requests: [ModelRequest] = []
    init(_ turns: [[ModelEvent]]) { self.turns = turns }
    func next(_ request: ModelRequest) throws -> [ModelEvent] {
        requests.append(request)
        guard !turns.isEmpty else { throw AssistantError.provider("Test script exhausted") }
        return turns.removeFirst()
    }
}
struct ScriptedBackend: ModelBackend {
    let id = "scripted"
    var networkDestination: String? = nil
    let script: ScriptedTurns
    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do { for event in try await script.next(request) { continuation.yield(event) }; continuation.finish() }
                catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}

final class EngineTests: XCTestCase, @unchecked Sendable {
    func testFailedCalculationReceiptsRemainFailedAndBlockFollowupFilesForBothBackendPaths() async throws {
        let failed = ToolCall(id: "failed-calculation", name: "run_javascript", arguments: .object([
            "code": .string("throw new Error('fixture calculation failure');"), "input_json": .string("null")
        ]))
        let invented = ToolCall(id: "invented-result", name: "create_artifact", arguments: .object([
            "filename": .string("totals.csv"), "content": .string("value\n18.5\n27.25\n14.75\n61.55")
        ]))
        let scripted = ScriptedBackend(script: ScriptedTurns([
            [.toolCall(failed), .completed], [.toolCall(invented), .completed],
            [.textDelta("The calculation failed; no result file was saved."), .completed]
        ]))
        let native = NativeToolFixture(calls: [failed, invented])
        for backend in [scripted as any ModelBackend, native as any ModelBackend] {
            let store = try makeTestStore(), conversation = Conversation()
            for try await _ in AssistantEngine(store: store).respond(conversation: conversation, text: "Calculate and save", captureIDs: [], backend: backend) { }
            let saved = try await store.loadConversation(conversation.id)
            let receipts = saved.messages.filter { $0.role == .tool }
            XCTAssertEqual(receipts.count, 2)
            XCTAssertTrue(receipts.allSatisfy { $0.state == .failed && $0.toolFailureDescription != nil })
            for receipt in receipts { XCTAssertEqual(try JSONValue.parse(receipt.text)["tool_succeeded"], .bool(false)) }
            let artifacts = try await store.artifacts(conversationID: conversation.id)
            XCTAssertTrue(artifacts.isEmpty)
        }
    }
    func testCancellationPreservesPartialResponseBeforeEngineBecomesIdle() async throws {
        let store = try makeTestStore()
        let engine = AssistantEngine(store: store)
        let conversation = Conversation()
        let signal = PartialSignal()
        let consumer = Task {
            for try await event in engine.respond(conversation: conversation, text: "Start", captureIDs: [], backend: SlowBackend()) {
                if case .conversation(let value) = event, value.messages.last?.text == "Partial" { await signal.markReady() }
            }
        }
        await signal.wait()
        consumer.cancel()
        _ = await consumer.result
        await engine.waitUntilIdle()
        let saved = try await store.loadConversation(conversation.id)
        XCTAssertEqual(saved.messages.last?.text, "Partial")
        XCTAssertEqual(saved.messages.last?.state, .interrupted)
    }
    func testFullToolLoopPersistsEvidenceBeforeFinalAnswer() async throws {
        let store = try makeTestStore()
        let capture = testCapture()
        try await store.saveCapture(capture, jpeg: Data([1, 2, 3]))
        let call = ToolCall(id: "one", name: "read_capture", arguments: .object(["capture_id": .string(capture.id.uuidString)]))
        let script = ScriptedTurns([[.toolCall(call), .completed], [.textDelta("The saved center depth is 1.5 m."), .completed]])
        let conversation = Conversation()
        var finished = false
        for try await event in AssistantEngine(store: store).respond(conversation: conversation, text: "Inspect", captureIDs: [capture.id], backend: ScriptedBackend(script: script)) {
            if case .finished = event { finished = true }
        }
        let saved = try await store.loadConversation(conversation.id)
        XCTAssertTrue(finished)
        XCTAssertEqual(saved.messages.map(\.role), [.user, .assistant, .tool, .assistant])
        XCTAssertTrue(saved.messages[2].text.contains("1.5"))
        let requests = await script.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[1].messages.last?.message.role, .tool)
    }

    func testNetworkConsentIsCheckedBeforeProviderOrUserMessageWrite() async throws {
        let store = try makeTestStore()
        let script = ScriptedTurns([[.textDelta("should not run"), .completed]])
        var backend = ScriptedBackend(script: script)
        backend.networkDestination = "https://example.test/v1"
        do {
            for try await _ in AssistantEngine(store: store).respond(conversation: Conversation(), text: "Private", captureIDs: [], backend: backend) { }
            XCTFail("Should require authorization")
        } catch AssistantError.networkNotAuthorized { }
        let requests = await script.requests
        let stored = try await store.conversations()
        XCTAssertTrue(requests.isEmpty)
        XCTAssertTrue(stored.isEmpty)
    }

    func testIncompleteStreamSavesPartialTextButExecutesNoTool() async throws {
        let store = try makeTestStore()
        let script = ScriptedTurns([[.textDelta("Partial answer"), .toolCall(ToolCall(id: "x", name: "read_capture", arguments: .object([:]))) ]])
        let conversation = Conversation()
        do {
            for try await _ in AssistantEngine(store: store).respond(conversation: conversation, text: "Hello", captureIDs: [], backend: ScriptedBackend(script: script)) { }
            XCTFail("Stream must have a completion marker")
        } catch AssistantError.incompleteResponse { }
        let saved = try await store.loadConversation(conversation.id)
        XCTAssertEqual(saved.messages.last?.text, "Partial answer")
        XCTAssertEqual(saved.messages.last?.state, .failed)
        XCTAssertTrue(saved.messages.last?.toolCalls.isEmpty == true)
        XCTAssertFalse(saved.messages.contains { $0.role == .tool })
    }

    func testInterruptedToolHistoryIsNotReplayedAsCompletedWork() async throws {
        let store = try makeTestStore()
        var conversation = Conversation()
        conversation.messages = [
            Message(role: .user, text: "Old request"),
            Message(role: .assistant, text: "", toolCalls: [ToolCall(id: "orphan", name: "read_capture", arguments: .object([:]))]),
        ]
        let script = ScriptedTurns([[.textDelta("Ready"), .completed]])
        for try await _ in AssistantEngine(store: store).respond(conversation: conversation, text: "Continue", captureIDs: [], backend: ScriptedBackend(script: script)) { }
        let sent = await script.requests
        XCTAssertTrue(sent[0].messages[1].message.toolCalls.isEmpty)
        XCTAssertTrue(sent[0].messages[1].message.text.contains("interrupted"))
    }
}

private struct NativeToolFixture: ModelBackend {
    let id = "native-tool-fixture"
    let networkDestination: String? = nil
    let calls: [ToolCall]
    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        AsyncThrowingStream { output in
            let task = Task {
                do {
                    guard let execute = request.toolExecutor else { throw AssistantError.invalidTool("Missing test executor") }
                    for call in calls {
                        let result = try await execute(call)
                        output.yield(.executedTool(call, result))
                    }
                    output.yield(.textDelta("The calculation failed; no result file was saved."))
                    output.yield(.completed); output.finish()
                } catch { output.finish(throwing: error) }
            }
            output.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}

private actor PartialSignal {
    private var ready = false
    private var waiter: CheckedContinuation<Void, Never>?
    func markReady() { ready = true; waiter?.resume(); waiter = nil }
    func wait() async {
        if ready { return }
        await withCheckedContinuation { waiter = $0 }
    }
}

private struct SlowBackend: ModelBackend {
    let id = "slow-test"
    let networkDestination: String? = nil
    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.textDelta("Partial"))
                do {
                    try await Task.sleep(for: .seconds(10))
                    continuation.yield(.completed); continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
