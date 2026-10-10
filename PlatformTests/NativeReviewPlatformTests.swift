import AssistantCore
import Foundation
import XCTest
@testable import PersonalAssistant

@MainActor
final class NativeReviewPlatformTests: XCTestCase {
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
