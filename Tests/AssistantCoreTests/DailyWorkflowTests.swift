import Foundation
import XCTest
@testable import AssistantCore

final class DailyWorkflowTests: XCTestCase, @unchecked Sendable {
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    func testAvailableTimeMergesOverlappingEventsAndStaysInsideDailyHours() throws {
        let start = date("2026-10-12T00:00:00-04:00"), end = date("2026-10-13T00:00:00-04:00")
        let blocks = [DateInterval(start: date("2026-10-12T09:00:00-04:00"), end: date("2026-10-12T11:00:00-04:00")), DateInterval(start: date("2026-10-12T10:30:00-04:00"), end: date("2026-10-12T12:00:00-04:00")), DateInterval(start: date("2026-10-12T13:00:00-04:00"), end: date("2026-10-12T14:00:00-04:00"))]
        let slots = try AvailabilityPlanner.slots(start: start, end: end, minutes: 60, dayStart: 9, dayEnd: 17, timeZone: TimeZone(identifier: "America/New_York")!, weekdaysOnly: true, busy: blocks)
        XCTAssertEqual(slots.map(\.start), [date("2026-10-12T12:00:00-04:00"), date("2026-10-12T14:00:00-04:00")])
        XCTAssertTrue(slots.allSatisfy { $0.duration == 3600 && $0.end <= date("2026-10-12T17:00:00-04:00") })
    }
    func testAvailabilityHandlesDaylightSavingAndWeekendChoice() throws {
        let slots = try AvailabilityPlanner.slots(start: date("2026-10-31T00:00:00-04:00"), end: date("2026-11-03T00:00:00-05:00"), minutes: 45, dayStart: 9, dayEnd: 17, timeZone: TimeZone(identifier: "America/New_York")!, weekdaysOnly: true, busy: [])
        XCTAssertEqual(slots.first?.start, date("2026-11-02T09:00:00-05:00")); XCTAssertEqual(slots.count, 1)
    }
    func testAllDayBusyWindowProvidesNoFalseAvailabilityAndBadRangesReject() throws {
        let start = date("2026-10-12T00:00:00Z"), end = date("2026-10-13T00:00:00Z")
        XCTAssertTrue(try AvailabilityPlanner.slots(start: start, end: end, minutes: 30, dayStart: 9, dayEnd: 17, timeZone: TimeZone(secondsFromGMT: 0)!, weekdaysOnly: false, busy: [.init(start: start, end: end)]).isEmpty)
        XCTAssertThrowsError(try AvailabilityPlanner.slots(start: end, end: start, minutes: 30, dayStart: 9, dayEnd: 17, timeZone: .current, weekdaysOnly: false, busy: []))
    }
    func testSaveOnlyInboxSurvivesRestartWithoutCreatingMessagesOrMemory() async throws {
        let store = try makeTestStore(); let chat = Conversation(title: "Ideas")
        try await store.save(chat)
        let entry = InboxEntry(text: "A useful idea", conversationID: chat.id, handling: .saveOnly)
        try await store.saveInboxEntry(entry)
        let reopened = try LocalStore(root: store.root)
        let notes = try await reopened.inboxEntries(); XCTAssertEqual(notes.map(\.id), [entry.id]); XCTAssertEqual(notes.first?.text, entry.text)
        XCTAssertEqual(notes.first?.handling, .saveOnly); XCTAssertEqual(notes.first?.conversationID, chat.id)
        XCTAssertEqual(notes.first!.createdAt.timeIntervalSince1970, entry.createdAt.timeIntervalSince1970, accuracy: 1)
        let saved = try await reopened.loadConversation(chat.id); XCTAssertTrue(saved.messages.isEmpty)
        let memories = try await reopened.memories(); XCTAssertTrue(memories.isEmpty)
        let work = try await reopened.unfinishedWork(); XCTAssertTrue(work.isEmpty)
    }
    func testInboxScopesDoNotLeakPrivateChatsOrUnassignedNotes() async throws {
        let store = try makeTestStore(); let current = Conversation(); var privateChat = Conversation(); privateChat.networkDisabled = true
        try await store.save(current); try await store.save(privateChat)
        try await store.saveInboxEntry(.init(text: "Visible note", conversationID: current.id, handling: .saveOnly))
        try await store.saveInboxEntry(.init(text: "Private note", conversationID: privateChat.id, handling: .later))
        try await store.saveInboxEntry(.init(text: "Unassigned note", conversationID: nil, handling: .later))
        let narrow = try await store.inboxContext(conversationID: current.id, remote: true, workspaceEnabled: false, query: "")
        XCTAssertEqual(narrow["items"]?.arrayValue?.count, 1)
        let workspace = try await store.inboxContext(conversationID: current.id, remote: true, workspaceEnabled: true, query: "")
        let text = try workspace.jsonString(); XCTAssertFalse(text.contains("Private note")); XCTAssertTrue(text.contains("Unassigned note"))
    }
    func testDeletingChatRemovesItsInboxAndQuestions() async throws {
        let store = try makeTestStore(); var chat = Conversation(); let user = Message(role: .user, text: "Task")
        chat.messages = [user]; try await store.save(chat)
        try await store.saveInboxEntry(.init(text: "A note", conversationID: chat.id, handling: .saveOnly))
        let question = try TaskQuestion(conversationID: chat.id, turnID: user.id, callID: "question", title: "Which day?", detail: "For planning", kind: .choice, choices: ["Monday", "Tuesday"])
        _ = try await store.saveQuestion(question)
        try await store.removeConversation(chat.id)
        let notes = try await store.inboxEntries(); XCTAssertTrue(notes.isEmpty)
        do { _ = try await store.question(question.id); XCTFail("Deleted question survived") } catch {}
    }
    func testQuestionAnswerIsRealUserInputInTheSameTaskAndSkipDoesNotInventAnAnswer() async throws {
        let store = try makeTestStore(); var chat = Conversation(); let user = Message(role: .user, text: "Plan tomorrow")
        chat.messages = [user]; try await store.save(chat)
        try await store.saveWorkTurn(.init(id: user.id, conversationID: chat.id, userMessageID: user.id, backendID: "fixture", goal: user.text))
        let question = try TaskQuestion(conversationID: chat.id, turnID: user.id, callID: "q", title: "Which time?", detail: "So I can find a slot", kind: .choice, choices: ["Morning", "Afternoon"])
        _ = try await store.saveQuestion(question)
        let response = try await store.answerQuestion(question.id, text: "After 2 pm, actually", captureIDs: [], skip: false)
        XCTAssertEqual(response.answer?.text, "After 2 pm, actually"); XCTAssertEqual(response.answer?.role, .user); XCTAssertEqual(response.answer?.replyToTaskID, user.id)
        chat.messages.append(response.answer!); try await store.save(chat)
        let work = try await store.unfinishedWork(); XCTAssertEqual(work.count, 1)
        let another = try TaskQuestion(conversationID: chat.id, turnID: user.id, callID: "q2", title: "Anything else?", detail: "", kind: .text, choices: [])
        _ = try await store.saveQuestion(another)
        let skipped = try await store.answerQuestion(another.id, text: "Ignored", captureIDs: [], skip: true)
        XCTAssertEqual(skipped.state, .skipped); XCTAssertNil(skipped.answer)
    }
    func testSupersededQuestionCannotModifyNewTaskAndRepeatedCallMustMatch() async throws {
        let store = try makeTestStore(); var chat = Conversation(); let user = Message(role: .user, text: "Plan")
        chat.messages = [user]; try await store.save(chat)
        try await store.saveWorkTurn(.init(id: user.id, conversationID: chat.id, userMessageID: user.id, backendID: "fixture", goal: user.text))
        let question = try TaskQuestion(conversationID: chat.id, turnID: user.id, callID: "q", title: "Which day?", detail: "", kind: .text, choices: [])
        _ = try await store.saveQuestion(question)
        let changed = try TaskQuestion(conversationID: chat.id, turnID: user.id, callID: "q", title: "A different question", detail: "", kind: .text, choices: [])
        do { _ = try await store.saveQuestion(changed); XCTFail("Changed replay accepted") } catch {}
        chat.messages.append(Message(role: .user, text: "A different task")); try await store.save(chat)
        let pending = try await store.pendingQuestions(); XCTAssertTrue(pending.isEmpty)
        do { _ = try await store.answerQuestion(question.id, text: "Monday", captureIDs: [], skip: false); XCTFail("Old answer accepted") } catch {}
    }
    func testSupplementalAnswerAndPhotoSurviveInterruptedReplyWithoutRepeatingQuestion() async throws {
        let store = try makeTestStore(), capture = testCapture(), recorder = QuestionRunRecorder()
        try await store.saveCapture(capture, jpeg: Data([1, 2, 3]))
        let engine = AssistantEngine(store: store), original = Conversation()
        let tool = ToolDefinition(name: "request_input", description: "Fixture", parameters: .object(["type": .string("object"), "properties": .object([:]), "required": .array([]), "additionalProperties": .bool(false)]))
        let execute: @Sendable (ToolCall) async throws -> ToolResult = { call in
            let identity = try XCTUnwrap(ToolExecutionContext.current)
            let question = try TaskQuestion(conversationID: original.id, turnID: identity.turnID, callID: identity.callID, title: "Show the label", detail: "", kind: .photo, choices: [])
            let saved = try await store.saveQuestion(question)
            let answered = try await store.answerQuestion(saved.id, text: "Here is the label", captureIDs: [capture.id], skip: false)
            var result = ToolResult(callID: call.id, name: call.name, succeeded: true, output: .object(["status": .string("answered")]))
            result.userResponse = answered.answer; return result
        }
        let backend = QuestionRunBackend(recorder: recorder)
        do { for try await _ in engine.respond(conversation: original, text: "Identify the item", captureIDs: [], backend: backend, additionalTools: [tool], additionalExecutor: execute) {} } catch {}
        let saved = try await store.loadConversation(original.id), work = try await store.unfinishedWork().first!
        XCTAssertEqual(saved.messages.filter(\.isRequest).count, 1)
        for try await _ in engine.resume(conversation: saved, turnID: work.id, backend: backend, additionalTools: [tool], additionalExecutor: execute) {}
        let final = try await store.loadConversation(original.id)
        XCTAssertEqual(final.messages.filter { $0.replyToTaskID != nil }.count, 1)
        let request = await recorder.latest
        XCTAssertEqual(request?.messages.flatMap(\.images).map(\.captureID), [capture.id])
        XCTAssertEqual(final.messages.last?.text, "The supplied label is available.")
    }
}
private actor QuestionRunRecorder {
    var calls = 0
    var latest: ModelRequest?
    func next(_ request: ModelRequest) -> Int { calls += 1; latest = request; return calls }
}
private struct QuestionRunBackend: ModelBackend {
    let recorder: QuestionRunRecorder
    var id: String { "question-test" }
    var networkDestination: String? { nil }
    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        AsyncThrowingStream { output in
            let task = Task {
                switch await recorder.next(request) {
                case 1: output.yield(.toolCall(.init(id: "question", name: "request_input", arguments: .object([:])))); output.yield(.completed); output.finish()
                case 2: output.yield(.textDelta("Checking the label")); output.finish(throwing: URLError(.networkConnectionLost))
                default: output.yield(.textDelta("The supplied label is available.")); output.yield(.completed); output.finish()
                }
            }
            output.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
