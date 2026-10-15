import XCTest
@testable import AssistantCore

final class Continuity130Tests: XCTestCase {
    func testReviewResolvedOnComputerReleasesPhoneWaiterAndNextOperation() async throws {
        actor Seen { var ids: [String] = []; func add(_ id: String) { ids.append(id) } }
        let seen = Seen()
        let phone = RemotePhoneOperations { call in
            await seen.add(call.id)
            if call.id == "review" { try await Task.sleep(for: .seconds(30)) }
        }
        await phone.enqueue([ToolCall(id: "review", name: "review_computer_action", arguments: .object([:])), ToolCall(id: "next", name: "get_app_context", arguments: .object([:]))])
        for _ in 0..<100 { if await seen.ids.contains("review") { break }; try await Task.sleep(for: .milliseconds(1)) }
        await phone.complete("review")
        for _ in 0..<100 { if await seen.ids.contains("next") { break }; try await Task.sleep(for: .milliseconds(1)) }
        try await phone.check()
        let calls = await seen.ids; XCTAssertEqual(calls, ["review", "next"])
        await phone.stop()
    }
    func testRevokedSharingRejectsTheNextToolBeforeExecution() async throws {
        let store = try makeTestStore(), turn = UUID()
        var chat = Conversation(); chat.messages = [Message(id: turn, role: .user, text: "Use this task")]
        chat.allowedNetworkDestinations.insert("computer:fixture"); try await store.save(chat)
        try await store.saveWorkTurn(WorkTurn(id: turn, conversationID: chat.id, userMessageID: turn, backendID: "companion:fixture", destination: "computer:fixture", goal: "Task"))
        let broker = AssistantTools(store: store, conversationID: chat.id, captureIDs: [], sandbox: JavaScriptSandbox(), remote: true, operationScope: turn, networkDestination: "computer:fixture")
        chat.allowedNetworkDestinations = []; try await store.save(chat)
        do { _ = try await broker.execute(ToolCall(id: "next", name: "get_capabilities", arguments: .object([:]))); XCTFail("Revocation must be checked at execution") }
        catch AssistantError.networkNotAuthorized { }
        catch { XCTFail("Unexpected revocation error: \(error)") }
    }
    func testRemoteQuestionReceiptClosesTheLocalPendingOperationExactlyOnce() async throws {
        let store = try makeTestStore(), turn = UUID()
        var chat = Conversation(); let user = Message(id: turn, role: .user, text: "Prepare a report"); chat.messages = [user]
        chat.allowedNetworkDestinations.insert("computer:fixture"); try await store.save(chat)
        try await store.saveWorkTurn(WorkTurn(id: turn, conversationID: chat.id, userMessageID: turn, backendID: "companion:fixture", destination: "computer:fixture", goal: "Report"))
        let call = ToolCall(id: "q", name: "request_input", arguments: .object(["question": .string("Label?")]))
        _ = try await store.beginToolOperation(call, conversationID: chat.id, turnID: turn)
        try await store.setOperationWaitingForReview(turnID: turn, callID: call.id, waiting: true)
        let result = ToolResult(callID: call.id, name: call.name, succeeded: true, output: .object(["status": .string("answered"), "answer": .string("Blue")]))
        let projected = [Message(role: .assistant, text: "", toolCalls: [call]), Message(role: .tool, text: try result.modelText(), toolCallID: call.id)]
        for _ in 0..<2 { try await store.commitCompanionTranscript(projected, receipts: [result], prefix: [user], conversationID: chat.id, turnID: turn, destination: "computer:fixture") }
        let operations = try await store.toolOperations(turn)
        XCTAssertEqual(operations.count, 1); XCTAssertEqual(operations[0].awaitingReview, false)
        XCTAssertEqual(operations[0].result?.output["status"], .string("answered"))
    }
    func testQuotedAnswerNeedsRealUserEvidenceAndSourceChangesRetireDependentTask() async throws {
        let store = try makeTestStore(), target = UUID(), source = UUID()
        var chat = Conversation(); chat.messages = [Message(id: target, role: .user, text: "Prepare a report"), Message(id: source, role: .user, text: "Use Blue", containsLocalOnlyContext: true)]
        try await store.save(chat)
        try await store.saveWorkTurn(WorkTurn(id: target, conversationID: chat.id, userMessageID: target, backendID: "companion:fixture", goal: "Report"))
        let question = try await store.saveQuestion(TaskQuestion(conversationID: chat.id, turnID: target, callID: "q", title: "Which label?", detail: "For the report", kind: .choice, choices: ["Blue", "Green"]))
        do { _ = try await store.answerQuestion(question.id, text: "Green", captureIDs: [], skip: false, sourceMessageID: source); XCTFail("An invented answer must be rejected") } catch { }
        let answer = try await store.answerQuestion(question.id, text: "Blue", captureIDs: [], skip: false, sourceMessageID: source)
        XCTAssertEqual(answer.answerSourceMessageID, source); XCTAssertEqual(answer.answer?.containsLocalOnlyContext, true)
        let retry = try await store.answerQuestion(question.id, text: "Blue", captureIDs: [], skip: false, sourceMessageID: source)
        XCTAssertEqual(retry.answer?.id, answer.answer?.id, "A lost acknowledgement must not manufacture another user answer")
        _ = try await store.prepareMessageEdit(in: chat, messageID: source)
        let retired = try await store.workTurn(target); XCTAssertEqual(retired?.phase, .superseded)
    }
    func testCompactedReplayHasTheSameTextIdentityAndStateAsIndividualDeltas() throws {
        let job = UUID(), at = "2026-01-01T00:00:00Z"
        var raw = CompanionTranscript(jobID: job, providerID: "companion:fixture", health: false)
        var compact = CompanionTranscript(jobID: job, providerID: "companion:fixture", health: false)
        for index in 1...2000 { _ = try raw.apply(.object(["seq": .number(Double(index)), "recordedAt": .string(at), "type": .string("text_delta"), "item_id": .string("answer"), "text": .string("x")])) }
        _ = try compact.apply(.object(["seq": .number(1), "through_seq": .number(2000), "recordedAt": .string(at), "type": .string("text_delta"), "item_id": .string("answer"), "text": .string(String(repeating: "x", count: 2000))]))
        let completed: JSONValue = .object(["seq": .number(2001), "recordedAt": .string(at), "type": .string("status"), "status": .string("completed")])
        _ = try raw.apply(completed); _ = try compact.apply(completed)
        XCTAssertEqual(raw.messages, compact.messages); XCTAssertEqual(raw.cursor, compact.cursor)
        XCTAssertThrowsError(try compact.apply(.object(["seq": .number(2002), "through_seq": .number(2008), "type": .string("executed_tool")])))
    }
    func testOlderComputerQuestionAndReplySurviveANewerRequestWithoutReplacingIt() async throws {
        let store = try makeTestStore(), first = UUID(), next = UUID()
        var chat = Conversation(); chat.allowedNetworkDestinations.insert("computer:fixture")
        let firstUser = Message(id: first, role: .user, text: "Prepare the report")
        let secondUser = Message(id: next, role: .user, text: "A separate question"), newerAnswer = Message(role: .assistant, text: "Newer response stays intact")
        chat.messages = [firstUser, Message(role: .assistant, text: "Independent work is ready"), secondUser, newerAnswer]
        try await store.save(chat)
        try await store.saveWorkTurn(WorkTurn(id: first, conversationID: chat.id, userMessageID: first, backendID: "companion:fixture", destination: "computer:fixture", goal: "Report"))
        try await store.saveWorkTurn(WorkTurn(id: next, conversationID: chat.id, userMessageID: next, backendID: "companion:fixture", destination: "computer:fixture", goal: "Separate question"))
        let proposed = try TaskQuestion(conversationID: chat.id, turnID: first, callID: "q", title: "Which label?", detail: "For the report", kind: .choice, choices: ["Blue"])
        let question = try await store.saveQuestion(proposed)
        try await store.supersedeWork(in: chat.id, except: next, preservingComputerTasks: true)
        let pending = try await store.pendingQuestions(); XCTAssertEqual(pending.map(\.id), [question.id])
        let answered = try await store.answerQuestion(question.id, text: "Blue", captureIDs: [], skip: false)
        XCTAssertEqual(answered.answer?.replyToTaskID, first)
        let oldReply = Message(role: .assistant, text: "The report is complete with Blue", providerID: "companion:fixture")
        try await store.commitCompanionTranscript([oldReply], receipts: [], prefix: [firstUser], conversationID: chat.id, turnID: first, destination: "computer:fixture")
        let saved = try await store.loadConversation(chat.id)
        XCTAssertEqual(saved.messages.map(\.id), [first, oldReply.id, next, newerAnswer.id])
        XCTAssertEqual(saved.messages.last?.text, newerAnswer.text)
    }
    func testEditingAComputerRequestQueuesStopAndRejectsItsLateProjection() async throws {
        let store = try makeTestStore(), turn = UUID()
        var chat = Conversation(); chat.allowedNetworkDestinations.insert("computer:fixture")
        let user = Message(id: turn, role: .user, text: "Original task"); chat.messages = [user]
        try await store.save(chat)
        try await store.saveWorkTurn(WorkTurn(id: turn, conversationID: chat.id, userMessageID: turn, backendID: "companion:fixture", destination: "computer:fixture", goal: "Original"))
        var run = CompanionRunRecord(turnID: turn, connectionID: "computer:fixture", payload: .object([:])); run.jobID = UUID().uuidString; run.status = "running"
        try await store.saveCompanionRun(run)
        _ = try await store.prepareMessageEdit(in: chat, messageID: turn)
        let stopped = try await store.companionRun(turn); XCTAssertEqual(stopped?.stopRequested, true)
        do { try await store.commitCompanionTranscript([Message(role: .assistant, text: "Stale output")], receipts: [], prefix: [user], conversationID: chat.id, turnID: turn, destination: "computer:fixture"); XCTFail("Removed work must not be restored by a late event") }
        catch { }
        let result = try await store.loadConversation(chat.id); XCTAssertTrue(result.messages.isEmpty)
    }
    func testCheckpointKeepsCurrentRequestAndRejectsChangedSource() throws {
        var messages = [Message(role: .user, text: "Preserve the original identity")]
        for index in 0..<14 { messages.append(Message(role: .assistant, text: "Verified step \(index)")) }
        let cutoff = try XCTUnwrap(ContextCheckpoint.cutoff(in: messages))
        let checkpoint: JSONValue = .object(["source_count": .number(Double(cutoff)), "source_hash": .string(try ContextCheckpoint.fingerprint(Array(messages.prefix(cutoff)))), "summary": .string("Original identity preserved. Steps verified; remaining work is pending.")])
        let compacted = try XCTUnwrap(ContextCheckpoint.apply(checkpoint, to: messages))
        XCTAssertEqual(compacted.first?.id, messages.first?.id)
        XCTAssertTrue(compacted[1].text.contains("remaining work is pending"))
        XCTAssertEqual(messages.count, 15)
        messages[2].text = "The source changed"
        XCTAssertNil(try ContextCheckpoint.apply(checkpoint, to: messages))
    }
    func testThirtyPercentReserveAcrossContextPresets() {
        for capacity in [10_000, 16_384, 32_768, 65_536, 128_000, 256_000, 512_000, 1_000_000] {
            XCTAssertEqual(ContextReserve.amount(in: capacity), Int(ceil(Double(capacity) * 0.3)))
            let limits = ContextLimits(maximumTextBytes: capacity)
            XCTAssertEqual(limits.workingTextBytes + limits.compactionReserveBytes, capacity)
        }
        let plan = ModelContextBudget(model: "gpt-6.1-sol", requestedInputTokens: 1_000_000)
        XCTAssertEqual(plan.activeInputTokens, 700_000)
        XCTAssertEqual(plan.compactionReserveTokens, 300_000)
    }
    func testNewRequestFallbackNeverChangesSavedOwner() throws {
        XCTAssertEqual(try TaskRoutePolicy.newRequest(local: false, computerEnabled: true, computerReady: true, mobileReady: true), .computer)
        XCTAssertEqual(try TaskRoutePolicy.newRequest(local: false, computerEnabled: true, computerReady: false, mobileReady: true), .mobile)
        XCTAssertEqual(try TaskRoutePolicy.newRequest(local: false, computerEnabled: false, computerReady: true, mobileReady: true), .mobile)
        XCTAssertEqual(try TaskRoutePolicy.newRequest(local: true, computerEnabled: true, computerReady: true, mobileReady: true), .onDevice)
        XCTAssertThrowsError(try TaskRoutePolicy.newRequest(local: false, computerEnabled: true, computerReady: false, mobileReady: false))
        XCTAssertEqual(TaskRoutePolicy.savedOwner(backendID: "companion:original", destination: "computer:original"), .computer)
        XCTAssertEqual(TaskRoutePolicy.savedOwner(backendID: "responses:original", destination: "chatgpt-account:original"), .mobile)
    }
    func testPendingReceiptBecomesOneActualReceiptAfterReplay() throws {
        let call = ToolCall(id: "question", name: "request_input", arguments: .object([:]))
        let encoded = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(call))
        var transcript = CompanionTranscript(jobID: UUID(), providerID: "companion:test", health: false)
        let pending: JSONValue = .object(["seq": .number(1), "type": .string("pending_tool"), "call": encoded,
            "result": .object(["callID": .string(call.id), "name": .string(call.name), "succeeded": .bool(true), "output": .object(["status": .string("pending")])])])
        XCTAssertNil(try transcript.apply(pending))
        XCTAssertEqual(transcript.messages.filter { $0.role == .tool }.count, 1)
        let before = transcript.messages.first { $0.role == .tool }!.id
        let finished: JSONValue = .object(["seq": .number(2), "type": .string("executed_tool"), "call": encoded,
            "result": .object(["callID": .string(call.id), "name": .string(call.name), "succeeded": .bool(true), "output": .object(["status": .string("answered"), "answer": .string("Blue")])])])
        XCTAssertNotNil(try transcript.apply(finished))
        XCTAssertEqual(transcript.messages.filter { $0.role == .tool }.count, 1)
        XCTAssertEqual(transcript.messages.first { $0.role == .tool }!.id, before)
        XCTAssertTrue(transcript.messages.first { $0.role == .tool }!.text.contains("Blue"))
        XCTAssertNil(try transcript.apply(finished))
    }
    func testPhoneQuestionDoesNotBlockIndependentSubscriptionAndRunsOnce() async throws {
        actor Gate {
            var started = 0
            var waiter: CheckedContinuation<Void, Never>?
            func hold() async { started += 1; await withCheckedContinuation { waiter = $0 } }
            func release() { waiter?.resume(); waiter = nil }
        }
        let gate = Gate(), phone = RemotePhoneOperations { _ in await gate.hold() }
        let question = ToolCall(id: "same", name: "request_input", arguments: .object([:]))
        await phone.enqueue([question, question])
        for _ in 0..<100 { if await gate.started > 0 { break }; try await Task.sleep(for: .milliseconds(1)) }
        // A server transcript can continue while this native question is open.
        var transcript = CompanionTranscript(jobID: UUID(), providerID: "companion:test", health: false)
        _ = try transcript.apply(.object(["seq": .number(1), "type": .string("text_delta"), "text": .string("Independent calculation finished")]))
        XCTAssertTrue(transcript.messages[0].text.contains("finished"))
        let count = await gate.started; XCTAssertEqual(count, 1)
        await gate.release(); await phone.stop()
    }
}
