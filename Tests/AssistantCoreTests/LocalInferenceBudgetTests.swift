import XCTest
@testable import AssistantCore

final class LocalInferenceBudgetTests: XCTestCase {
    func testReportedPhoneHeadroomCanPlan32KForExactQwenLanguageWeights() {
        let allowance = Int64(3.05 * 1_073_741_824)
        let plan = LocalInferenceBudget(weightBytes: 2_367_118_848, availableBytes: allowance, requestedMemoryGiB: 8, optimizedTextRuntime: true)
        XCTAssertTrue(plan.fits)
        XCTAssertEqual(plan.selectedContextTokens, 32_768)
        XCTAssertGreaterThanOrEqual(plan.inputTokens, 28_000)
        XCTAssertLessThan(plan.workingBytes, allowance)
        let fullVision = LocalInferenceBudget(weightBytes: 3_034_300_695, availableBytes: allowance, requestedMemoryGiB: 8)
        XCTAssertFalse(fullVision.fits, "A text-fit estimate must not promise that the larger vision runtime also fits.")
    }
    func testMeasuredWarmFootprintIncludesTokenizerAndDoesNotDoubleChargeLoading() {
        let weights: Int64 = 2_367_118_848, available = Int64(3.05 * 1_073_741_824)
        let resident = weights + 128 * 1_024 * 1_024
        let cold = LocalInferenceBudget(weightBytes: weights, availableBytes: available, optimizedTextRuntime: true)
        let warm = LocalInferenceBudget(weightBytes: weights, availableBytes: available - resident, residentBytes: resident, optimizedTextRuntime: true)
        XCTAssertEqual(cold, warm)
        let heavier = resident + 160 * 1_024 * 1_024
        let adapted = LocalInferenceBudget(weightBytes: weights, availableBytes: available - heavier, residentBytes: heavier, optimizedTextRuntime: true)
        XCTAssertTrue(adapted.fits); XCTAssertLessThan(adapted.selectedContextTokens, cold.selectedContextTokens)
    }
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
