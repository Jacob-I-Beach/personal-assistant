import AssistantCore
import XCTest
@testable import PersonalAssistant

@MainActor
final class ActivityLifecyclePlatformTests: XCTestCase {
    func testHandoffPreservesTheExecutionWindowAndRealProgress() {
        let turn = UUID(), window = ResponseCompletionWindow()
        window.begin { _ in XCTFail("The fixture should not expire") }
        window.identifyTurn(turn); window.received(bytes: 42)
        XCTAssertTrue(window.hasExecutionTime)
        window.handoff()
        XCTAssertEqual(ResponseCompletionWindow.diagnostic(for: turn)["state"], .string("handoff_in_progress"))
        window.begin(preservingCurrent: true) { _ in XCTFail("The fixture should not expire") }
        XCTAssertTrue(window.hasExecutionTime)
        XCTAssertEqual(ResponseCompletionWindow.diagnostic(for: turn)["state"], .string("continuing_on_computer"))
        XCTAssertEqual(ResponseCompletionWindow.diagnostic(for: turn)["processed_bytes"], .number(42))
        window.end(success: true)
        XCTAssertFalse(window.hasExecutionTime)
        XCTAssertEqual(ResponseCompletionWindow.diagnostic(for: turn)["state"], .string("completed"))
    }

    func testReadyAndWaitingStatesRemainTruthfulWhenTheActivityBecomesStale() throws {
        let ready = AssistantActivityAttributes.ContentState(title: "Your reply is ready", detail: "Tap to open the answer.", phase: "ready", updatedAt: Date(), finishedAt: Date())
        XCTAssertEqual(ready.headline(stale: true), "Your reply is ready")
        XCTAssertTrue(ready.isReady); XCTAssertFalse(ready.isWorking)
        let waiting = AssistantActivityAttributes.ContentState(title: "Your answer is needed", detail: "Open the question.", phase: "waiting", updatedAt: Date())
        XCTAssertEqual(waiting.headline(stale: true), "Your answer is needed")
        XCTAssertFalse(waiting.isReady)
        let running = AssistantActivityAttributes.ContentState(title: "Checking sources", detail: "", phase: "working", updatedAt: Date())
        XCTAssertEqual(running.headline(stale: true), "Updating your progress")
        XCTAssertFalse(running.headline(stale: true).contains("ready"))
        XCTAssertLessThan(try JSONEncoder().encode(ready).count, 4096)
    }
}
