import XCTest
@testable import AssistantCore

final class LocalInferenceBudgetTests: XCTestCase {
    func testPhoneAllowanceControlsContextEvenWhenEightGiBAreRequested() {
        let plan = LocalInferenceBudget(weightBytes: 3_034_000_000, availableBytes: 5_000_000_000,
            requestedMemoryGiB: 8, requestedContextTokens: 262_144)
        XCTAssertLessThan(plan.workingBytes, 5_000_000_000)
        XCTAssertLessThan(plan.selectedContextTokens, 65_536)
        XCTAssertLessThan(plan.inputTokens + plan.responseTokens, plan.selectedContextTokens)
    }
    func testLoadedWeightsAreNotSubtractedTwice() {
        let fresh = LocalInferenceBudget(weightBytes: 3_000_000_000, availableBytes: 7_000_000_000)
        let loaded = LocalInferenceBudget(weightBytes: 3_000_000_000, availableBytes: 4_000_000_000, residentBytes: 3_000_000_000)
        XCTAssertEqual(fresh, loaded)
    }
    func testLowMemoryRejectsModelAndNeverAdvertisesNegativeContext() {
        let plan = LocalInferenceBudget(weightBytes: 3_000_000_000, availableBytes: 1_000_000_000)
        XCTAssertFalse(plan.fits); XCTAssertEqual(plan.maximumContextTokens, 0); XCTAssertTrue(plan.presets.isEmpty)
    }
    func testLargeAllowanceHasUsefulContextWithoutExceedingNativeWindow() {
        let plan = LocalInferenceBudget(weightBytes: 3_034_000_000, availableBytes: 10_000_000_000,
            requestedMemoryGiB: 8, requestedContextTokens: 1_000_000)
        XCTAssertTrue(plan.presets.contains(131_072)); XCTAssertEqual(plan.maximumContextTokens, 262_144)
        XCTAssertEqual(plan.workingBytes, 8 * 1_073_741_824)
    }
}
