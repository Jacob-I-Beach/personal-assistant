import XCTest
@testable import AssistantCore

final class CompanionTranscriptTests: XCTestCase, @unchecked Sendable {
    func testReplayRetainsMessageIdentityAndQuestionBeforeAnswer() throws {
        let id = UUID(), turn = UUID()
        var answer = Message(role: .user, text: "Saturday"); answer.replyToTaskID = turn
        let encodedAnswer = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(answer))
        let events: [JSONValue] = [
            .object(["seq": .number(1), "type": .string("response_begin")]),
            .object(["seq": .number(2), "type": .string("text_delta"), "text": .string("Let’s choose a day."), "phase": .string("commentary")]),
            .object(["seq": .number(3), "type": .string("executed_tool"), "call": .object(["id": .string("question"), "name": .string("request_input"), "arguments": .object(["question": .string("Which day?")])]),
                     "result": .object(["succeeded": .bool(true), "output": .object(["question": .string("Which day?"), "answer": .string("Saturday")]), "userResponse": encodedAnswer])]),
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
