import XCTest
@testable import AssistantCore

final class Continuity130Tests: XCTestCase {
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
        try transcript.apply(.object(["seq": .number(1), "type": .string("text_delta"), "text": .string("Independent calculation finished")]))
        XCTAssertTrue(transcript.messages[0].text.contains("finished"))
        let count = await gate.started; XCTAssertEqual(count, 1)
        await gate.release(); await phone.stop()
    }
}
