import AssistantCore
import SwiftUI
import XCTest
@testable import PersonalAssistant

@MainActor
final class ChatViewportPlatformTests: XCTestCase {
    func testDismantlingAnOldControllerDoesNotDisconnectTheCurrentJumpButton() {
        let viewport = ChatViewport()
        let old = ChatScrollController(viewport: viewport)
        let current = ChatScrollController(viewport: viewport)
        old.detach()
        XCTAssertTrue(viewport.controller === current)
        current.detach()
        XCTAssertNil(viewport.controller)
    }
    func testJumpToLatestWorksWithoutWaitingForNewContent() throws {
        let viewport = ChatViewport(), controller = ChatScrollController(viewport: ChatViewport())
        controller.attach(viewport)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 700))
        window.rootViewController = controller; window.makeKeyAndVisible()
        controller.update(AnyView(Text("Synthetic long content").frame(width: 393, height: 5000)), conversationID: UUID(), streaming: false, hasMessages: true)
        controller.view.layoutIfNeeded()
        let scroll = try XCTUnwrap(controller.view as? UIScrollView)
        XCTAssertGreaterThan(scroll.contentSize.height, 1000)
        scroll.setContentOffset(CGPoint(x: 0, y: 250), animated: false)
        viewport.jumpToLatest()
        XCTAssertEqual(scroll.contentOffset.y, max(0, scroll.contentSize.height - scroll.bounds.height), accuracy: 1)
        controller.detach(); window.isHidden = true
    }
    func testFeedbackAndContextPreferencesMigrateWithHealthReviewStillSeparate() throws {
        let settings = try JSONDecoder().decode(ModelSettings.self, from: Data("{}".utf8))
        XCTAssertTrue(settings.hapticsEnabled)
        XCTAssertFalse(settings.confirmNewConnectedChats)
        XCTAssertTrue(settings.contextTokensByModel.isEmpty)
        XCTAssertFalse(settings.healthToolsEnabled)
        XCTAssertFalse(settings.planningConnectedAccess)
    }
}
