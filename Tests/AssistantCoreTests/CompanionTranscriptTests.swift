import XCTest
@testable import AssistantCore

final class CompanionTranscriptTests: XCTestCase, @unchecked Sendable {
    func testHandoffReplacesTheProvisionalToolWithoutDuplicatingItsCallOrOpaqueState() async throws {
        let store = try makeTestStore(), turn = UUID()
        let call = ToolCall(id: "python", name: "run_python", arguments: .object([:]))
        var chat = Conversation()
        let user = Message(id: turn, role: .user, text: "Finish the calculation.")
        var invocation = Message(role: .assistant, text: "I am calculating it.", state: .interrupted)
        invocation.toolCalls = [call]
        invocation.continuation = ProviderContinuation(providerID: "phone", items: [.object(["type": .string("function_call"), "call_id": .string(call.id)])])
        chat.messages = [user, invocation, Message(role: .tool, text: "Awaiting the computer receipt", state: .interrupted, toolCallID: call.id)]
        var work = WorkTurn(id: turn, conversationID: chat.id, userMessageID: turn, backendID: "synthetic-handoff", goal: user.text, configuration: .object(["handoff_message_count": .number(3)]))
        work.phase = .interrupted
        try await store.save(chat); try await store.saveWorkTurn(work)
        let engine = AssistantEngine(store: store)
        for try await _ in engine.resume(conversation: chat, turnID: turn, backend: HandoffReceiptBackend(call: call)) { }
        let saved = try await store.loadConversation(chat.id)
        XCTAssertEqual(saved.messages.flatMap(\.toolCalls).map(\.id), [call.id])
        XCTAssertEqual(saved.messages.filter { $0.role == .tool }.count, 1)
        XCTAssertNil(saved.messages.first(where: { $0.id == invocation.id })?.continuation)
        XCTAssertEqual(saved.messages.last?.text, "The result is 42.")
        let completed = try await store.workTurn(turn)
        XCTAssertEqual(completed?.phase, .completed)
    }
    func testComputerFileHandlesDoNotEmbedDatasetBytesInTheModelRequest() throws {
        let backend = try NetworkModelBackend(baseURL: URL(string: "https://api.openai.com/v1")!, model: "synthetic", wireProtocol: .responses, chatGPTAccountID: "synthetic")
        let file = ModelFile(filename: "data.csv", mediaType: "text/csv", data: Data("synthetic private rows".utf8), id: UUID())
        let request = ModelRequest(instructions: "Use the computer file handle.", messages: [.init(message: Message(role: .user, text: "Calculate the total."), files: [file])], tools: [])
        let body = try backend.responsesBody(request, includeFileContents: false).jsonString()
        XCTAssertFalse(body.contains("input_file")); XCTAssertFalse(body.contains(file.data.base64EncodedString()))
        XCTAssertTrue(try backend.responsesBody(request).jsonString().contains("input_file"))
    }
    func testReplayRetainsMessageIdentityAndQuestionBeforeAnswer() throws {
        let id = UUID(), turn = UUID()
        var answer = Message(role: .user, text: "Saturday"); answer.replyToTaskID = turn
        let encodedAnswer = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(answer))
        let events: [JSONValue] = [
            .object(["seq": .number(1), "type": .string("response_begin")]),
            .object(["seq": .number(2), "type": .string("text_delta"), "text": .string("Let’s choose a day."), "phase": .string("commentary")]),
            .object(["seq": .number(3), "type": .string("executed_tool"), "call": .object(["id": .string("question"), "name": .string("request_input"), "arguments": .object(["question": .string("Which day?")])]),
                     "result": .object(["callID": .string("question"), "name": .string("request_input"), "succeeded": .bool(true), "output": .object(["question": .string("Which day?"), "answer": .string("Saturday")]), "userResponse": encodedAnswer])]),
            .object(["seq": .number(4), "type": .string("text_delta"), "text": .string("Saturday works.")]),
            .object(["seq": .number(5), "type": .string("status"), "status": .string("completed")])
        ]
        var original = CompanionTranscript(jobID: id, providerID: "computer", health: false)
        var replay = CompanionTranscript(jobID: id, providerID: "computer", health: false)
        for event in events { _ = try original.apply(event); _ = try replay.apply(event) }
        XCTAssertEqual(original.messages.map(\.id), replay.messages.map(\.id))
        XCTAssertEqual(original.messages.map(\.role), [.assistant, .tool, .user, .assistant])
        XCTAssertEqual(original.messages[1].toolCallID, "question")
        XCTAssertEqual(original.messages[2].replyToTaskID, turn)
        XCTAssertEqual(original.messages.last?.text, "Saturday works.")
        _ = try original.apply(events.last!)
        XCTAssertEqual(original.messages.count, 4)
        XCTAssertThrowsError(try original.apply(.object(["seq": .number(7), "type": .string("status")])))
    }
    func testRemoteOutboxPreservesOriginalRequestAcrossReconnect() async throws {
        let store = try makeTestStore(), id = UUID()
        var record = CompanionRunRecord(turnID: id, connectionID: "computer:one", payload: .object(["request_key": .string(id.uuidString)]))
        try await store.saveCompanionRun(record)
        record.jobID = UUID().uuidString; record.status = "running"
        try await store.saveCompanionRun(record)
        let saved = try await store.companionRun(id)
        XCTAssertEqual(saved?.jobID, record.jobID); XCTAssertEqual(saved?.payload, record.payload)
        XCTAssertEqual(saved?.stopRequested, false)
        record.stopRequested = true; record.status = "cancelled"
        try await store.saveCompanionRun(record)
        var late = saved!; late.status = "running"
        try await store.saveCompanionRun(late)
        let stopped = try await store.companionRun(id)
        XCTAssertEqual(stopped?.stopRequested, true); XCTAssertEqual(stopped?.status, "cancelled")
    }
}

private struct HandoffReceiptBackend: RemoteTaskBackend {
    let call: ToolCall
    let id = "synthetic-handoff"
    let networkDestination: String? = nil
    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> { AsyncThrowingStream { $0.finish(throwing: AssistantError.incompleteResponse) } }
    func runTask(_ request: ModelRequest) -> AsyncThrowingStream<RemoteTaskEvent, any Error> {
        AsyncThrowingStream { output in
            let task = Task {
                do {
                    let receipt = ToolResult(callID: call.id, name: call.name, succeeded: true, output: .object(["answer": .number(42)]))
                    var invocation = Message(role: .assistant, text: ""); invocation.toolCalls = [call]
                    let messages = [invocation, Message(role: .tool, text: try receipt.modelText(), toolCallID: call.id), Message(role: .assistant, text: "The result is 42.")]
                    try await request.commitRemoteTranscript?(messages, [receipt]); output.yield(.transcript(messages))
                    output.yield(.completed); output.finish()
                } catch { output.finish(throwing: error) }
            }
            output.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
