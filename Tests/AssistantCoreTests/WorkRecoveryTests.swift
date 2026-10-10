import XCTest
@testable import AssistantCore

final class WorkRecoveryTests: XCTestCase, @unchecked Sendable {
    func testGrowingNativeCatalogPreservesWorkingContextThroughDiscovery() async throws {
        let store = try makeTestStore(), chat = Conversation()
        try await store.save(chat)
        let native = ToolDefinition(name: "synthetic_native", description: String(repeating: "Native capability description. ", count: 600), parameters: .object(["type": .string("object"), "properties": .object([:]), "required": .array([]), "additionalProperties": .bool(false)]))
        let tools = AssistantTools(store: store, conversationID: chat.id, captureIDs: [], sandbox: JavaScriptSandbox(), contextBudget: 32_768, additionalDefinitions: [native])
        XCTAssertEqual(Set(tools.definitions.map(\.name)), ["get_capabilities", "find_tools", "use_tool"])
        let selection = try ContextPlanner.select([Message(role: .user, text: String(repeating: "A real working request. ", count: 200))], instructions: AssistantInstructions.base, tools: tools.definitions, limits: .init())
        XCTAssertEqual(selection.messages.count, 1)
    }
    func testExecutedNativeReceiptSurvivesBeforeTheProviderCouldReportIt() async throws {
        let store = try makeTestStore(); var chat = Conversation()
        let user = Message(role: .user, text: "Create a durable note")
        let call = ToolCall(id: "native-completed", name: "create_artifact", arguments: .object(["filename": .string("durable.txt"), "content": .string("Saved before interruption")]))
        chat.messages = [user, Message(role: .assistant, text: "Preparing the note.", state: .streaming, toolCalls: [call])]
        try await store.save(chat)
        let tools = AssistantTools(store: store, conversationID: chat.id, captureIDs: [], sandbox: JavaScriptSandbox(), operationScope: user.id)
        let result = try await tools.execute(call); XCTAssertTrue(result.succeeded)
        let work = WorkTurn(id: user.id, conversationID: chat.id, userMessageID: user.id, backendID: "recovery-fixture", goal: user.text)
        try await store.saveWorkTurn(work)
        let recorder = RecoveryRecorder(initialCalls: 2)
        for try await _ in AssistantEngine(store: store).resume(conversation: try await store.loadConversation(chat.id), turnID: work.id, backend: RecoveryBackend(recorder: recorder)) {}
        let artifacts = try await store.artifacts(); XCTAssertEqual(artifacts.count, 1)
        let request = await recorder.latest()
        XCTAssertEqual(request?.messages.flatMap { $0.message.toolCalls }.filter { $0.id == call.id }.count, 1)
        XCTAssertEqual(request?.messages.filter { $0.message.role == .tool && $0.message.toolCallID == call.id }.count, 1)
    }
    func testColdInterruptionCannotExecuteAPartiallyStreamedToolCall() async throws {
        let store = try makeTestStore()
        var chat = Conversation(); let user = Message(role: .user, text: "An unfinished request")
        chat.messages = [user, Message(role: .assistant, text: "", state: .streaming, toolCalls: [.init(id: "partial", name: "create_artifact", arguments: .object(["filename": .string("must-not-exist.txt"), "content": .string("Unvalidated tool call")]))])]
        try await store.save(chat)
        let recorder = RecoveryRecorder(initialCalls: 2)
        let work = WorkTurn(id: user.id, conversationID: chat.id, userMessageID: user.id, backendID: "recovery-fixture", goal: user.text)
        try await store.saveWorkTurn(work)
        let restored = try await store.loadConversation(chat.id)
        for try await _ in AssistantEngine(store: store).resume(conversation: restored, turnID: work.id, backend: RecoveryBackend(recorder: recorder)) {}
        let artifacts = try await store.artifacts(); XCTAssertTrue(artifacts.isEmpty)
    }
    func testCompletedEffectIsReusedAndUncertainEffectIsNotRepeated() async throws {
        let store = try makeTestStore(), chat = Conversation(), scope = UUID()
        try await store.save(chat)
        let tools = AssistantTools(store: store, conversationID: chat.id, captureIDs: [], sandbox: JavaScriptSandbox(), operationScope: scope)
        let create = ToolCall(id: "create", name: "create_artifact", arguments: .object(["filename": .string("note.txt"), "content": .string("A useful note")]))
        let first = try await tools.execute(create), second = try await tools.execute(create)
        XCTAssertTrue(first.succeeded); XCTAssertEqual(first.output, second.output)
        let artifacts = try await store.artifacts(); XCTAssertEqual(artifacts.count, 1)
        let uncertain = ToolCall(id: "uncertain", name: "create_artifact", arguments: .object(["filename": .string("unknown.txt"), "content": .string("Must not repeat")]))
        _ = try await store.beginToolOperation(uncertain, conversationID: chat.id, turnID: scope)
        let result = try await tools.execute(uncertain)
        XCTAssertFalse(result.succeeded); XCTAssertEqual(result.output["status"], .string("outcome_unknown"))
        let after = try await store.artifacts(); XCTAssertEqual(after.count, 1)
    }
    func testResumePreservesToolReceiptsAndDoesNotInsertAPretendUserMessage() async throws {
        let store = try makeTestStore(), engine = AssistantEngine(store: store), recorder = RecoveryRecorder()
        let backend = RecoveryBackend(recorder: recorder)
        let original = Conversation()
        do { for try await _ in engine.respond(conversation: original, text: "Create a note", captureIDs: [], backend: backend) {} } catch {}
        await engine.waitUntilIdle()
        let interrupted = try await store.loadConversation(original.id)
        let pending = try await store.unfinishedWork()
        let work = try XCTUnwrap(pending.first)
        XCTAssertEqual(work.phase, .interrupted)
        for try await _ in engine.resume(conversation: interrupted, turnID: work.id, backend: backend) {}
        let final = try await store.loadConversation(original.id)
        XCTAssertEqual(final.messages.filter { $0.role == .user }.map(\.text), ["Create a note"])
        XCTAssertEqual(final.messages.last?.text, "The existing note is ready.")
        let artifacts = try await store.artifacts(); XCTAssertEqual(artifacts.count, 1)
        let finished = try await store.workTurn(work.id)
        XCTAssertEqual(finished?.phase, .completed); XCTAssertEqual(finished?.rounds, 3); XCTAssertEqual(finished?.resumes, 1)
        let request = await recorder.latest()
        XCTAssertTrue(request?.instructions.contains("No new user message was sent") == true)
        XCTAssertTrue(request?.messages.contains(where: { $0.message.role == .tool }) == true)
    }
    func testCancelledTaskCannotResumeWithoutANewUserDecision() async throws {
        let store = try makeTestStore(), engine = AssistantEngine(store: store)
        var chat = Conversation(); let user = Message(role: .user, text: "Stopped work")
        chat.messages = [user]; try await store.save(chat)
        var work = WorkTurn(id: UUID(), conversationID: chat.id, userMessageID: user.id, backendID: "recovery-fixture", goal: user.text)
        work.phase = .cancelled; try await store.saveWorkTurn(work)
        do { for try await _ in engine.resume(conversation: chat, turnID: work.id, backend: RecoveryBackend(recorder: RecoveryRecorder())) {}; XCTFail("Cancelled work restarted") } catch {}
        let saved = try await store.workTurn(work.id); XCTAssertEqual(saved?.phase, .cancelled)
    }
}
private actor RecoveryRecorder {
    var calls = 0
    init(initialCalls: Int = 0) { calls = initialCalls }
    var request: ModelRequest?
    func next(_ request: ModelRequest) -> Int { calls += 1; self.request = request; return calls }
    func latest() -> ModelRequest? { request }
}
private struct RecoveryBackend: ModelBackend {
    let recorder: RecoveryRecorder
    var id: String { "recovery-fixture" }
    var networkDestination: String? { nil }
    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        AsyncThrowingStream { output in
            let task = Task {
                switch await recorder.next(request) {
                case 1:
                    output.yield(.toolCall(ToolCall(id: "saved-note", name: "create_artifact", arguments: .object(["filename": .string("note.txt"), "content": .string("A useful note")]))))
                    output.yield(.completed); output.finish()
                case 2: output.finish(throwing: AssistantError.provider("Synthetic connection interruption"))
                default: output.yield(.textDelta("The existing note is ready.")); output.yield(.completed); output.finish()
                }
            }
            output.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
