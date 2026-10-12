import XCTest
@testable import AssistantCore

final class ActivityCoherenceTests: XCTestCase {
    func testResearchAndCitationsAreVisibleBeforeTheAnswerFinishesAndReplayKeepsIdentity() throws {
        let job = UUID()
        var projection = CompanionTranscript(jobID: job, providerID: "synthetic", health: false)
        let web: JSONValue = .object(["id": .string("search"), "type": .string("web_search_call"), "status": .string("completed"), "action": .object(["type": .string("search"), "query": .string("city walking trails")])])
        let events: [JSONValue] = [
            .object(["seq": .number(1), "type": .string("response_begin")]),
            .object(["seq": .number(2), "type": .string("web_activity"), "output_index": .number(0), "item": web]),
            .object(["seq": .number(3), "type": .string("text_delta"), "item_id": .string("answer"), "output_index": .number(1), "content_index": .number(0), "text": .string("Here is the comparison.")]),
            .object(["seq": .number(4), "type": .string("annotation"), "item_id": .string("answer"), "output_index": .number(1), "content_index": .number(0), "annotation": .object(["type": .string("url_citation"), "url": .string("https://example.test/trails"), "title": .string("Trail guide")])])
        ]
        for event in events { _ = try projection.apply(event) }
        let streaming = try XCTUnwrap(projection.messages.last)
        XCTAssertEqual(streaming.state, .streaming)
        XCTAssertEqual(streaming.displayParts.map(\.kind), [.web, .text])
        XCTAssertEqual(streaming.displayCitations.first?.title, "Trail guide")
        var restored = CompanionTranscript(jobID: job, providerID: "synthetic", health: false)
        for event in events { _ = try restored.apply(event) }
        XCTAssertEqual(restored.messages.map(\.id), projection.messages.map(\.id))
        XCTAssertEqual(restored.messages.last?.displayParts, streaming.displayParts)
        let final: JSONValue = .object(["id": .string("answer"), "type": .string("message"), "content": .array([.object(["type": .string("output_text"), "text": .string("Here is the comparison.")])])])
        _ = try projection.apply(.object(["seq": .number(5), "type": .string("continuation"), "output": .array([web, final])]))
        XCTAssertEqual(projection.messages.last?.displayParts.map(\.id), streaming.displayParts.map(\.id))
    }

    func testLateResearchUpdatesKeepProviderOrderWithoutDuplicatingRows() throws {
        var projection = CompanionTranscript(jobID: UUID(), providerID: "synthetic", health: false)
        _ = try projection.apply(.object(["seq": .number(1), "type": .string("text_delta"), "output_index": .number(2), "item_id": .string("answer"), "text": .string("A draft answer")]))
        let web: JSONValue = .object(["type": .string("web_search_call"), "id": .string("web"), "status": .string("in_progress")])
        _ = try projection.apply(.object(["seq": .number(2), "type": .string("web_activity"), "output_index": .number(1), "item": web]))
        _ = try projection.apply(.object(["seq": .number(3), "type": .string("web_activity"), "output_index": .number(1), "item": .object(["type": .string("web_search_call"), "id": .string("web"), "status": .string("completed")])]))
        XCTAssertEqual(projection.messages.last?.displayParts.map(\.kind), [.web, .text])
        XCTAssertEqual(projection.messages.last?.displayParts.count, 2)
        XCTAssertEqual(projection.messages.last?.displayParts.first?.web?.status, "completed")
    }

    func testReconnectDoesNotPublishOlderPagesAndLegacyRecordsWaitForASnapshot() throws {
        var saved = CompanionReplayGate(lastSyncedCursor: 700)
        XCTAssertFalse(saved.canPublish(cursor: 512, snapshotCursor: 900))
        XCTAssertTrue(saved.canPublish(cursor: 800, snapshotCursor: 950))
        var legacy = CompanionReplayGate(lastSyncedCursor: nil)
        XCTAssertFalse(legacy.canPublish(cursor: 512, snapshotCursor: 900))
        XCTAssertTrue(legacy.canPublish(cursor: 900, snapshotCursor: 1000))
        let record = try JSONDecoder().decode(CompanionRunRecord.self, from: Data("{\"turnID\":\"00000000-0000-4000-8000-000000000001\",\"connectionID\":\"test\",\"payload\":{},\"status\":\"running\",\"stopRequested\":false}".utf8))
        XCTAssertNil(record.lastSyncedCursor)
    }

    func testToolSummaryNamesActualWorkAndDoesNotClaimFailedActionsSucceeded() throws {
        var chat: [Message] = [], receipts: [Message] = []
        for index in 0..<3 {
            let call = ToolCall(id: "read-\(index)", name: "read_conversation", arguments: .object([:]))
            chat.append(Message(role: .assistant, text: "", toolCalls: [call]))
            let receipt = Message(role: .tool, text: "{}", toolCallID: call.id)
            chat.append(receipt); receipts.append(receipt)
        }
        let failed = Message(role: .tool, text: "{\"status\":\"failed\",\"error\":\"Synthetic failure\"}", state: .failed, toolCallID: "failed")
        receipts.append(failed); chat.append(failed)
        let result = ActivitySummaries.tools(receipts, in: chat)
        XCTAssertEqual(result.title, "Read 3 earlier chats")
        XCTAssertTrue(result.needsAttention)
        XCTAssertTrue(result.detail.contains("1 needs attention"))
        let allFailed = ActivitySummaries.tools([failed], in: chat)
        XCTAssertEqual(allFailed.title, "Work needs attention")
    }

    func testWebSummaryDistinguishesSearchesFromPagesAndKeepsTheSubject() {
        let summary = ActivitySummaries.web([
            WebActivity(status: "completed", queries: ["city walking trails"]),
            WebActivity(status: "in_progress", action: "open_page")
        ])
        XCTAssertEqual(summary.title, "Checking 1 search · 1 page")
        XCTAssertEqual(summary.detail, "city walking trails")
        XCTAssertTrue(summary.running)
        XCTAssertFalse(summary.needsAttention)
    }
}
