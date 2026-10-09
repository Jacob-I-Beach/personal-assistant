import Foundation
import XCTest
@testable import AssistantCore

final class WatchTests: XCTestCase, @unchecked Sendable {
    func testDuplicateDeliveryDoesNotCreateDuplicateWorkAndReplySurvivesRestart() async throws {
        let store = try makeTestStore()
        let request = WatchRequest(text: "A synthetic Watch request")
        let first = try await store.enqueueWatchRequest(request)
        let second = try await store.enqueueWatchRequest(request)
        XCTAssertTrue(first); XCTAssertFalse(second)
        let queued = try await store.queuedWatchRequests()
        XCTAssertEqual(queued.count, 1)
        let reply = WatchReply(requestID: request.id, conversationID: nil, state: .complete, message: "Saved response", modelName: "Fixture")
        try await store.saveWatchReply(reply)
        let reopened = try LocalStore(root: store.root)
        let restored = try await reopened.watchReply(request.id)
        XCTAssertEqual(restored, reply)
        let remaining = try await reopened.queuedWatchRequests()
        XCTAssertTrue(remaining.isEmpty)
        var changed = request; changed.text = "Different contents"
        do { _ = try await reopened.enqueueWatchRequest(changed); XCTFail("Changed duplicate accepted") } catch {}
    }
    func testExpiredAndOversizedRequestsAreRejected() {
        XCTAssertFalse(WatchRequest(text: "old", createdAt: Date().addingTimeInterval(-90_000)).isValid())
        XCTAssertFalse(WatchRequest(text: String(repeating: "x", count: 8001)).isValid())
        XCTAssertFalse(WatchRequest(text: "   ").isValid())
    }
}
