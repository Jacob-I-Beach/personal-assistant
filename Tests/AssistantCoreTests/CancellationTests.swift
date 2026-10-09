import Foundation
import XCTest
@testable import AssistantCore

final class CancellationTests: XCTestCase, @unchecked Sendable {
    func testCancelledWaiterReturnsPromptlyWithoutCancellingSharedProducer() async throws {
        let producer = Task<Int, Error> { try await Task.sleep(for: .milliseconds(600)); return 42 }
        let first = Task { try await CancellableTaskValue.value(of: producer) }
        let second = Task { try await CancellableTaskValue.value(of: producer) }
        try await Task.sleep(for: .milliseconds(20))
        let start = ContinuousClock.now
        first.cancel()
        do { _ = try await first.value; XCTFail("Cancelled waiter returned a value") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertLessThan(start.duration(to: .now), .milliseconds(400))
        let value = try await second.value
        XCTAssertEqual(value, 42)
        XCTAssertFalse(producer.isCancelled)
    }
}
