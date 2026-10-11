import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import AssistantCore

final class LongTaskTests: XCTestCase, @unchecked Sendable {
    func testOversizedToolTurnCompactsWithoutChangingStoredEvidenceOrUserRequest() async throws {
        let store = try makeTestStore()
        var chat = Conversation()
        chat.messages = [Message(role: .user, text: "Find the decisions already made and finish the report.")]
        for index in 0..<12 {
            let call = ToolCall(id: "read-\(index)", name: "read_history", arguments: .object(["message_id": .string(UUID().uuidString), "offset": .string("0")]))
            var invocation = Message(role: .assistant, text: "", toolCalls: [call])
            invocation.continuation = ProviderContinuation(providerID: "fixture", items: [.object(["type": .string("reasoning"), "encrypted_content": .string(String(repeating: "encrypted", count: 3000))])])
            chat.messages.append(invocation)
            chat.messages.append(Message(role: .tool, text: try JSONValue.object(["result": .string(String(repeating: "Saved evidence 🌎 ", count: 1000)), "status": .string("completed"), "tool_succeeded": .bool(true)]).jsonString(), toolCallID: call.id))
        }
        try await store.save(chat)
        let selection = try ContextPlanner.select(chat.messages, instructions: "fixture", tools: [], limits: .init(maximumTextBytes: 32_768))
        XCTAssertGreaterThan(selection.compactedMessageCount, 0)
        XCTAssertLessThan(try ContextPlanner.textCost(selection.messages), 32_768 - 2048)
        XCTAssertEqual(selection.messages.first, chat.messages.first)
        XCTAssertEqual(selection.messages.filter { $0.role == .tool }.count, 12)
        XCTAssertTrue(selection.messages.allSatisfy { $0.continuation == nil })
        let receipt = try JSONValue.parse(selection.messages.last!.text)
        XCTAssertEqual(receipt["status"], .string("completed"))
        XCTAssertNotNil(receipt["saved_result_message_id"])
        let saved = try await store.loadConversation(chat.id)
        XCTAssertEqual(saved.messages.last?.text, chat.messages.last?.text)
    }
    func testHugeCompletedArgumentsBecomeSavedEvidenceWithoutOrphanCalls() throws {
        let user = Message(role: .user, text: "Build a table")
        let call = ToolCall(id: "done", name: "run_javascript", arguments: .object(["code": .string(String(repeating: "some code; ", count: 20_000))]))
        let result = Message(role: .tool, text: "{\"status\":\"outcome_unknown\",\"error\":\"Check the original before repeating\"}", toolCallID: call.id)
        let selection = try ContextPlanner.select([user, Message(role: .assistant, text: "", toolCalls: [call]), result], instructions: "test", tools: [], limits: .init(maximumTextBytes: 8000))
        XCTAssertEqual(selection.messages.filter { $0.role == .user }, [user])
        XCTAssertTrue(selection.messages.flatMap(\.toolCalls).isEmpty)
        XCTAssertTrue(selection.messages.allSatisfy { $0.role != .tool })
        XCTAssertTrue(selection.messages.last!.text.contains("outcome_unknown"))
        XCTAssertLessThan(try ContextPlanner.textCost(selection.messages), 6000)
    }
    func testUserRequestIsNeverSilentlyTruncated() {
        XCTAssertThrowsError(try ContextPlanner.select([Message(role: .user, text: String(repeating: "x", count: 50_000))], instructions: "fixture", tools: [], limits: .init(maximumTextBytes: 8000))) {
            guard case AssistantError.contextCapacity = $0 else { return XCTFail("Wrong capacity failure") }
        }
    }
    func testHistoryDoesNotSearchOrBrowseEarlierToolResultJSON() async throws {
        let store = try makeTestStore()
        var chat = Conversation()
        chat.messages = [Message(role: .user, text: "Siri capture decisions"), Message(role: .tool, text: "{\"query\":\"Siri capture decisions\"}", toolCallID: "old"), Message(role: .assistant, text: "Use the shared inbox.")]
        try await store.save(chat)
        let matches = try await store.searchMessages("Siri", conversationID: chat.id)
        XCTAssertEqual(matches.map(\.id), [chat.messages[0].id])
        let page = try await store.browseConversationMessages(chat.id, remote: true)
        XCTAssertEqual(page.map(\.role), [.user, .assistant])
        let exact = try await store.message(chat.messages[1].id, in: chat.id)
        XCTAssertEqual(exact.text, chat.messages[1].text)
    }
    func testLegacyUnfinishedTurnDisappearsWhenAnotherUserRequestFollows() async throws {
        let store = try makeTestStore()
        var chat = Conversation(); let first = Message(role: .user, text: "Original"), next = Message(role: .user, text: "Continue")
        chat.messages = [first]; try await store.save(chat)
        let work = WorkTurn(id: first.id, conversationID: chat.id, userMessageID: first.id, backendID: "fixture", goal: first.text)
        try await store.saveWorkTurn(work)
        let before = try await store.unfinishedWork(); XCTAssertEqual(before.count, 1)
        chat.messages.append(next); try await store.save(chat)
        let after = try await store.unfinishedWork(); XCTAssertTrue(after.isEmpty)
        try await store.supersedeWork(in: chat.id, except: next.id)
        let old = try await store.workTurn(first.id); XCTAssertEqual(old?.phase, .superseded)
    }
    func testActivityGroupsKeepStableIdentityAndDoNotHideTextOrInteractiveObjects() {
        let first = Message(role: .tool, text: "{}", toolCallID: "read1"), second = Message(role: .tool, text: "{}", toolCallID: "read2")
        var messages = [Message(role: .user, text: "Inspect"), first]
        let stableID = ChatTimeline.items(messages).last?.id
        messages += [Message(role: .assistant, text: "", toolCalls: [.init(id: "read2", name: "read_history", arguments: .object([:]))]), second]
        XCTAssertEqual(ChatTimeline.items(messages).last?.id, stableID)
        XCTAssertEqual(ChatTimeline.items(messages).last?.messages.count, 2)
        messages += [Message(role: .assistant, text: "Here is what I found."), Message(role: .tool, text: "{}", toolCallID: "read3")]
        XCTAssertEqual(ChatTimeline.items(messages).count, 4)
        messages += [Message(role: .assistant, text: "", toolCalls: [.init(id: "map", name: "prepare_route", arguments: .object([:]))]), Message(role: .tool, text: "{}", toolCallID: "map")]
        XCTAssertFalse(ChatTimeline.items(messages).last!.isActivity)
    }
    func testReadableReceiptsKeepSourcesAndUnknownOutcomesWithoutTransportNoise() {
        let nodes = ReceiptDetails.nodes(.object(["status": .string("outcome_unknown"), "operation_id": .string("call_private"), "result": .array([.object(["title": .string("A saved decision"), "text": .string("Use the original."), "message_id": .string("opaque")])])]))
        XCTAssertFalse(nodes.contains { $0.title == "Operation id" })
        XCTAssertTrue(nodes.first { $0.title == "Status" }?.value?.contains("not confirmed") == true)
        XCTAssertEqual(nodes.first { $0.title == "Found" }?.children.first?.title, "A saved decision")
    }
    func testRetryClassificationIsBoundedAndDoesNotRetryAuthorizationQuotaOrInvalidCalls() {
        let policy = ResponseRetryPolicy()
        for attempt in 1...5 { XCTAssertNotNil(policy.delay(after: URLError(.networkConnectionLost), retry: attempt)) }
        XCTAssertNil(policy.delay(after: URLError(.networkConnectionLost), retry: 6))
        for status in [400, 401, 403, 404, 307] { XCTAssertNil(policy.delay(after: ModelHTTPError(status: status), retry: 1)) }
        XCTAssertNil(policy.delay(after: ModelHTTPError(status: 429, code: "insufficient_quota"), retry: 1))
        XCTAssertNil(policy.delay(after: ModelHTTPError(status: 503, retryAfter: 100), retry: 1))
        XCTAssertNil(policy.delay(after: AssistantError.contextCapacity, retry: 1))
        XCTAssertNil(policy.delay(after: CancellationError(), retry: 1))
        XCTAssertEqual(policy.delay(after: ModelHTTPError(status: 503, retryAfter: 3), retry: 1), 3)
    }
    func testNetworkRetryReplacesPartialTextAndCommitsOnlyTheCompletedAttempt() async throws {
        let transport = RetryFixture(failures: 1)
        let backend = try NetworkModelBackend(baseURL: URL(string: "http://localhost/v1")!, model: "fixture", wireProtocol: .chatCompletions, transport: transport, retryPolicy: .init(baseDelay: 0))
        let store = try makeTestStore(); var chat = Conversation(); chat.allowedNetworkDestinations.insert(backend.networkDestination!)
        var statuses: [String] = []
        for try await event in AssistantEngine(store: store).respond(conversation: chat, text: "Finish", captureIDs: [], backend: backend) {
            if case .activity(let status) = event { statuses.append(status) }
        }
        let saved = try await store.loadConversation(chat.id)
        XCTAssertEqual(saved.messages.last?.text, "The finished answer.")
        XCTAssertEqual(saved.messages.filter { $0.role == .assistant }.count, 1)
        XCTAssertTrue(statuses.contains("Retrying 1/5"))
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2); XCTAssertEqual(requests[0].httpBody, requests[1].httpBody)
    }
    func testRetryStopsAfterFiveAndPreservesPartialWork() async throws {
        let transport = RetryFixture(failures: 10)
        let backend = try NetworkModelBackend(baseURL: URL(string: "http://localhost/v1")!, model: "fixture", wireProtocol: .chatCompletions, transport: transport, retryPolicy: .init(baseDelay: 0))
        do { for try await _ in backend.stream(.init(instructions: "test", messages: [], tools: [])) {}; XCTFail("Should stop") }
        catch let error as URLError { XCTAssertEqual(error.code, .networkConnectionLost) }
        let count = await transport.requests.count; XCTAssertEqual(count, 6)
    }
    func testTaskDiagnosticExportOmitsPersonalContentAndRetainsActualCancellation() async throws {
        let store = try makeTestStore(); var chat = Conversation()
        let user = Message(role: .user, text: "PRIVATE MESSAGE TEXT")
        chat.messages = [user]; try await store.save(chat)
        var work = WorkTurn(id: user.id, conversationID: chat.id, userMessageID: user.id, backendID: "private-account-identifier", goal: user.text)
        work.reason = "PRIVATE ERROR CONTENT"; try await store.saveWorkTurn(work)
        let call = ToolCall(id: "example", name: "compose_text_message", arguments: .object(["body": .string("PRIVATE DRAFT")]))
        _ = try await store.beginToolOperation(call, conversationID: chat.id, turnID: user.id)
        try await store.finishToolOperation(call, turnID: user.id, result: .init(callID: call.id, name: call.name, succeeded: true, output: .object(["status": .string("cancelled"), "body": .string("PRIVATE RESULT")])) )
        try await store.recordNetworkRetry(user.id)
        let report = try await store.taskDiagnostics(user.id), text = try report.jsonString()
        XCTAssertFalse(text.contains("PRIVATE")); XCTAssertFalse(text.contains("private-account"))
        XCTAssertEqual(report["actions"]?.arrayValue?.first?["status"], .string("cancelled"))
        XCTAssertEqual(report["network_retries"], .number(1))
    }
    func testOutputLimitAndAuthorizationFailuresDoNotStartTransientRetry() throws {
        var decoder = ModelWireDecoder(wireProtocol: .responses)
        let event = ServerSentEvent(data: "{\"type\":\"response.incomplete\",\"response\":{\"incomplete_details\":{\"reason\":\"max_output_tokens\"}}}")
        XCTAssertThrowsError(try decoder.consume(event)) { XCTAssertNil(ResponseRetryPolicy().delay(after: $0, retry: 1)) }
    }
    func testCancellationDuringRetryBackoffDoesNotSendAnotherRequest() async throws {
        let transport = RetryFixture(failures: 10)
        let backend = try NetworkModelBackend(baseURL: URL(string: "http://localhost/v1")!, model: "fixture", wireProtocol: .chatCompletions, transport: transport, retryPolicy: .init(baseDelay: 30))
        let consumer = Task { for try await _ in backend.stream(.init(instructions: "fixture", messages: [], tools: [])) {} }
        for _ in 0..<100 { if await transport.requests.count > 0 { break }; try await Task.sleep(for: .milliseconds(5)) }
        consumer.cancel(); _ = try? await consumer.value
        try await Task.sleep(for: .milliseconds(30))
        let count = await transport.requests.count; XCTAssertEqual(count, 1)
    }
    func testReviewNotYetPresentedCanBeRebuiltButPresentedReviewCannotReplay() async throws {
        let store = try makeTestStore(); let chat = Conversation(), turnID = UUID()
        try await store.save(chat)
        let definition = ToolDefinition(name: "review_fixture", description: "Fixture", parameters: .object(["type": .string("object"), "properties": .object(["value": .object(["type": .string("string")])]), "required": .array([.string("value")]), "additionalProperties": .bool(false)]))
        let tools = AssistantTools(store: store, conversationID: chat.id, captureIDs: [], sandbox: JavaScriptSandbox(), operationScope: turnID, additionalDefinitions: [definition], additionalExecutor: { call in
            ToolResult(callID: call.id, name: call.name, succeeded: true, output: .object(["status": .string("saved")]))
        })
        let call = ToolCall(id: "review", name: definition.name, arguments: .object(["value": .string("fixture")]))
        _ = try await store.beginToolOperation(call, conversationID: chat.id, turnID: turnID)
        try await store.setOperationWaitingForReview(turnID: turnID, callID: call.id, waiting: true)
        let ready = try await tools.execute(call); XCTAssertTrue(ready.succeeded)
        let second = ToolCall(id: "already-presented", name: definition.name, arguments: call.arguments)
        _ = try await store.beginToolOperation(second, conversationID: chat.id, turnID: turnID)
        try await store.setOperationWaitingForReview(turnID: turnID, callID: second.id, waiting: false)
        let unknown = try await tools.execute(second); XCTAssertEqual(unknown.output["status"], .string("outcome_unknown"))
    }
}

private actor RetryFixture: HTTPStreamingTransport {
    let failures: Int
    var requests: [URLRequest] = []
    init(failures: Int) { self.failures = failures }
    private func record(_ request: URLRequest) -> Bool { requests.append(request); return requests.count <= failures }
    nonisolated func stream(_ request: URLRequest) -> AsyncThrowingStream<Data, any Error> {
        AsyncThrowingStream { output in
            let task = Task {
                if await record(request) {
                    output.yield(Data("data: {\"choices\":[{\"delta\":{\"content\":\"Unfinished text\"}}]}\n\n".utf8))
                    output.finish(throwing: URLError(.networkConnectionLost))
                } else {
                    output.yield(Data("data: {\"choices\":[{\"delta\":{\"content\":\"The finished answer.\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n".utf8))
                    output.finish()
                }
            }
            output.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
