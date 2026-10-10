import AssistantCore
import Foundation
import XCTest
@testable import PersonalAssistant

@MainActor
final class NativeReviewPlatformTests: XCTestCase {
    func testInterruptedReviewIsNotRecordedAsAUserCancellation() async throws {
        let model = AppModel(); try await model.waitUntilReady()
        let request = NativeActionRequest(kind: .approval, title: "Fixture", detail: "Synthetic review", arguments: .object([:]))
        let task = Task { try await model.reviewNativeAction(request) }
        for _ in 0..<50 { if model.isPendingNativeAction(request.id) { break }; try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(model.isPendingNativeAction(request.id))
        task.cancel()
        let status = try await task.value
        XCTAssertEqual(status, "interrupted"); XCTAssertFalse(model.isPendingNativeAction(request.id))
    }
    func testCancelMessageEditRestoresDraftAndAttachmentsWithoutChangingHistory() async throws {
        let model = AppModel(); try await model.waitUntilReady()
        let originalCapture = UUID(), draftCapture = UUID()
        var message = Message(role: .user, text: "Original", captureIDs: [originalCapture])
        message.imageSelections = [originalCapture.uuidString: [.init(x: 0.2, y: 0.3)]]
        model.conversation.messages = [message, Message(role: .assistant, text: "Later answer")]
        model.draft = "Unsent draft"; model.attachedCaptureIDs = [draftCapture]
        model.beginEditing(message)
        XCTAssertEqual(model.editingMessageID, message.id)
        XCTAssertEqual(model.draft, "Original")
        XCTAssertEqual(model.selectedImagePoints[originalCapture.uuidString]?.count, 1)
        model.draft = "Changed but not sent"; model.cancelEditing()
        XCTAssertNil(model.editingMessageID); XCTAssertEqual(model.draft, "Unsent draft")
        XCTAssertEqual(model.attachedCaptureIDs, [draftCapture]); XCTAssertTrue(model.selectedImagePoints.isEmpty)
        XCTAssertEqual(model.conversation.messages.last?.text, "Later answer")
    }
    func testDismissalResolvesOnlyTheMatchingNativeRequest() async throws {
        let model = AppModel()
        try await model.waitUntilReady()
        let request = NativeActionRequest(kind: .exportFile, title: "Fixture", detail: "", arguments: .object([:]),
                                          fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("fixture.txt"))
        let review = Task { try await model.reviewNativeAction(request) }
        defer { review.cancel() }
        for _ in 0..<50 {
            if model.isPendingNativeAction(request.id) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(model.isPendingNativeAction(request.id))
        model.resolveNativeAction("approved", for: UUID())
        XCTAssertTrue(model.isPendingNativeAction(request.id))
        // SwiftUI clears an item's binding before the disappearing picker reports cancellation.
        model.nativeAction = nil
        model.resolveNativeAction("cancelled", for: request.id)
        let status = try await review.value
        XCTAssertEqual(status, "cancelled")
        XCTAssertFalse(model.isPendingNativeAction(request.id))
        model.resolveNativeAction("completed", for: request.id)
        XCTAssertNil(model.nativeAction)
    }
}
