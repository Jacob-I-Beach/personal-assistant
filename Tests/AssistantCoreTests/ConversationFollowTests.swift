import XCTest
@testable import AssistantCore

final class ConversationFollowTests: XCTestCase {
    func testReaderDetachesAndOnlyReattachesAtTheBottom() {
        var state = ConversationFollow()
        XCTAssertTrue(state.isFollowing)
        state.beginReading()
        state.userReached(distanceFromBottom: 70)
        XCTAssertFalse(state.isFollowing, "Being near the bottom is not the same as returning to it.")
        state.userReached(distanceFromBottom: 2)
        XCTAssertTrue(state.isFollowing)
        state.beginReading()
        XCTAssertFalse(state.isFollowing)
        state.followLatest()
        XCTAssertTrue(state.isFollowing)
    }
    func testStreamingMotionDoesNotBounceForTransientHeightReductions() {
        var offset = 100.0
        for bottom in [120.0, 118, 125, 124, 148, 145, 180, 179] {
            let next = ConversationFollow.advance(current: offset, bottom: bottom, elapsed: 1.0 / 60, scale: 3)
            XCTAssertGreaterThanOrEqual(next, offset)
            XCTAssertLessThanOrEqual(next, max(offset, bottom))
            offset = next
        }
        for _ in 0..<120 { offset = ConversationFollow.advance(current: offset, bottom: 180, elapsed: 1.0 / 60, scale: 3) }
        XCTAssertEqual(offset, 180, accuracy: 0.001)
        XCTAssertEqual(ConversationFollow.advance(current: 180, bottom: 177, elapsed: 0.02, scale: 3), 180)
    }
}
