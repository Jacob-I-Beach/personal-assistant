import XCTest
@testable import AssistantCore

/// Exercises the real engine assembler, with the same byte ceiling as Apple's
/// on-device backend. The scripted transport replaces inference only.
final class ProductionContextTests: XCTestCase, @unchecked Sendable {
    func testRealSmallContextIncludesAttachmentsAndSavedMemoryWithoutOverflow() async throws {
        let store = try makeTestStore(), chat = Conversation(), capture = testCapture()
        try await store.saveCapture(capture, jpeg: Data([1]))
        try await store.saveMemory(SavedMemory(title: "Response preference", text: "Use concrete examples.", conversationID: chat.id))
        let script = ScriptedTurns([[.textDelta("Saved image metadata available."), .completed]])
        let backend = SmallContextBackend(script: script)
        for try await _ in AssistantEngine(store: store).respond(conversation: chat, text: "What can you read from this photo?", captureIDs: [capture.id], backend: backend,
            automaticMemory: true, appContext: .init(planningConnected: true, planningSharedWithModel: true, locationEnabled: true, computerEnabled: true, contactsEnabled: true)) { }
        let sent = await script.requests
        let request = try XCTUnwrap(sent.first)
        XCTAssertTrue(request.instructions.contains(capture.id.uuidString))
        XCTAssertTrue(request.instructions.contains("Use concrete examples"))
        XCTAssertTrue(request.messages.allSatisfy { $0.images.isEmpty })
        XCTAssertLessThanOrEqual(try ContextPlanner.requestTextCost(request) + ContextPlanner.responseReserveBytes, backend.contextLimits.maximumTextBytes)
    }

    func testNativeToolRolloverRetainsReceiptAndDoesNotReplaySideEffect() async throws {
        let store = try makeTestStore(), chat = Conversation(), recorder = RolloverRecorder()
        for try await _ in AssistantEngine(store: store).respond(conversation: chat, text: "Save a note", captureIDs: [], backend: RolloverBackend(recorder: recorder), appContext: .init()) { }
        let saved = try await store.loadConversation(chat.id), artifacts = try await store.artifacts(conversationID: chat.id)
        XCTAssertEqual(artifacts.count, 1)
        XCTAssertEqual(saved.messages.filter { $0.role == .tool }.count, 1)
        XCTAssertEqual(saved.messages.last?.text, "The note is saved.")
        XCTAssertFalse(saved.messages.contains { $0.state == .failed || $0.state == .interrupted })
        let requests = await recorder.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests[1].messages.contains { $0.message.role == .tool })
    }

    func testSmallToolResultsAreBoundedButOriginalCanBeReadExactly() async throws {
        let store = try makeTestStore(), chat = Conversation()
        try await store.save(chat)
        let definition = ToolDefinition(name: "read_fixture", description: "Read synthetic source", parameters: .object(["type": .string("object"), "properties": .object([:])]))
        let original = String(repeating: "\u{1}🌍\" data ", count: 1000)
        let broker = AssistantTools(store: store, conversationID: chat.id, captureIDs: [], sandbox: JavaScriptSandbox(), compactCatalog: true, contextBudget: 10_000,
            additionalDefinitions: [definition], additionalExecutor: { call in .init(callID: call.id, name: call.name, succeeded: true, output: .object(["text": .string(original)])) })
        let result = try await broker.execute(.init(id: "read-once", name: "read_fixture", arguments: .object([:])))
        let text = try broker.modelText(result), bounded = try JSONValue.parse(text)
        XCTAssertLessThanOrEqual(text.utf8.count, 2000); XCTAssertEqual(bounded["truncated"], .bool(true)); XCTAssertEqual(result.output["text"], .string(original))
        let page = try await broker.execute(.init(id: "page", name: "read_tool_result", arguments: .object(["operation_id": .string("read-once"), "offset": .string("0")])))
        XCTAssertTrue(page.succeeded); XCTAssertTrue(try result.modelText().hasPrefix(page.output["text"]!.stringValue!)); XCTAssertNotNil(page.output["next_offset"]?.numberValue)
        let capabilities = try await broker.execute(.init(id: "caps", name: "get_capabilities", arguments: .object([:])))
        XCTAssertLessThan(try capabilities.modelText().utf8.count, 1800)
    }
    func testFreshAppleRequestFitsWithRealAppOrientationAndMemoryEnabled() async throws {
        let store = try makeTestStore(), script = ScriptedTurns([[.textDelta("Hello"), .completed]])
        let backend = SmallContextBackend(script: script)
        for try await _ in AssistantEngine(store: store).respond(conversation: Conversation(), text: "Hello", captureIDs: [],
            backend: backend, automaticMemory: true, appContext: .init(computerEnabled: true)) { }
        let requests = await script.requests
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        let toolBytes = try request.tools.reduce(0) { $0 + $1.name.utf8.count + $1.description.utf8.count + (try $1.parameters.jsonString()).utf8.count + 100 }
        let inputBytes = try ContextPlanner.textCost(request.messages.map(\.message))
        print("AFM production fixture: instructions=\(request.instructions.utf8.count), tools=\(toolBytes), input=\(inputBytes), replyReserve=2048, limit=\(backend.contextLimits.maximumTextBytes) bytes")
        XCTAssertLessThanOrEqual(request.instructions.utf8.count + toolBytes + inputBytes + 2048, backend.contextLimits.maximumTextBytes)
        XCTAssertEqual(request.tools.map(\.name), ["get_capabilities", "find_tools", "use_tool"])
    }

    func testToolDiscoveryDoesNotInventMatchesForUnrelatedQuery() async throws {
        let store = try makeTestStore(), chat = Conversation()
        try await store.save(chat)
        let broker = AssistantTools(store: store, conversationID: chat.id, captureIDs: [], sandbox: JavaScriptSandbox(), compactCatalog: true, contextBudget: 10_000)
        let result = try await broker.execute(.init(id: "missing", name: "find_tools", arguments: .object(["query": .string("xylophone_unsupplied_zzzz")])) )
        XCTAssertEqual(result.output.arrayValue?.count, 0)
    }
}

private struct SmallContextBackend: ModelBackend {
    let id = "apple:on-device"
    let networkDestination: String? = nil
    let contextLimits = ContextLimits.appleOnDevice
    let script: ScriptedTurns
    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        ScriptedBackend(script: script).stream(request)
    }
}

private actor RolloverRecorder {
    var requests: [ModelRequest] = []
    func next(_ request: ModelRequest) -> Int { requests.append(request); return requests.count }
}
private struct RolloverBackend: ModelBackend {
    let id = "apple:on-device", networkDestination: String? = nil
    let contextLimits = ContextLimits.appleOnDevice
    let recorder: RolloverRecorder
    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        AsyncThrowingStream { output in
            let task = Task {
                do {
                    if await recorder.next(request) == 1 {
                        let call = ToolCall(id: "save-once", name: "create_artifact", arguments: .object(["filename": .string("note.txt"), "content": .string("Saved content")]))
                        let result = try await request.toolExecutor!(call)
                        output.yield(.executedTool(call, result)); output.yield(.contextWindowRollover)
                    } else { output.yield(.textDelta("The note is saved.")); output.yield(.completed) }
                    output.finish()
                } catch { output.finish(throwing: error) }
            }
            output.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
