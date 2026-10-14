import XCTest
@testable import AssistantCore

final class LocalInferenceBudgetTests: XCTestCase {
    func testReportedHeadroomDoesNotSilentlySatisfy64KWith32K() {
        let allowance = Int64(3.05 * 1_073_741_824)
        let plan = LocalInferenceBudget(weightBytes: 2_367_118_848, availableBytes: allowance, requestedMemoryGiB: 8, optimizedTextRuntime: true)
        XCTAssertFalse(plan.fits)
        XCTAssertEqual(plan.selectedContextTokens, 65_536)
        XCTAssertLessThan(plan.maximumContextTokens, 65_536)
        let smaller = LocalInferenceBudget(weightBytes: 2_367_118_848, availableBytes: allowance, requestedContextTokens: 32_768, optimizedTextRuntime: true)
        XCTAssertTrue(smaller.fits); XCTAssertEqual(smaller.selectedContextTokens, 32_768)
        XCTAssertEqual(smaller.attentionCacheBits, 4)
        XCTAssertLessThan(plan.workingBytes, allowance)
        let fullVision = LocalInferenceBudget(weightBytes: 3_034_300_695, availableBytes: allowance, requestedMemoryGiB: 8)
        XCTAssertFalse(fullVision.fits, "A text-fit estimate must not promise that the larger vision runtime also fits.")
    }
    func testMeasuredWarmFootprintIncludesTokenizerAndDoesNotDoubleChargeLoading() {
        let weights: Int64 = 2_367_118_848, available = Int64(3.05 * 1_073_741_824)
        let resident = weights + 128 * 1_024 * 1_024
        let cold = LocalInferenceBudget(weightBytes: weights, availableBytes: available, requestedContextTokens: 32_768, optimizedTextRuntime: true)
        let warm = LocalInferenceBudget(weightBytes: weights, availableBytes: available - resident, residentBytes: resident, requestedContextTokens: 32_768, optimizedTextRuntime: true)
        XCTAssertEqual(cold, warm)
        let heavier = resident + 160 * 1_024 * 1_024
        let adapted = LocalInferenceBudget(weightBytes: weights, availableBytes: available - heavier, residentBytes: heavier, requestedContextTokens: 32_768, optimizedTextRuntime: true)
        XCTAssertFalse(adapted.fits); XCTAssertEqual(adapted.selectedContextTokens, cold.selectedContextTokens)
    }
    func testPhoneAllowanceControlsContextEvenWhenEightGiBAreRequested() {
        let plan = LocalInferenceBudget(weightBytes: 3_034_000_000, availableBytes: 5_000_000_000,
            requestedMemoryGiB: 8, requestedContextTokens: 262_144)
        XCTAssertLessThan(plan.workingBytes, 5_000_000_000)
        XCTAssertFalse(plan.fits); XCTAssertEqual(plan.selectedContextTokens, 262_144)
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
    func test64KUsesHighestCachePrecisionThatFitsWithoutRequantizingWeights() {
        for (gib, bits) in [(6.0, Optional<Int>.none), (4.2, 8), (3.5, 4)] {
            let plan = LocalInferenceBudget(weightBytes: 2_367_118_848, availableBytes: Int64(gib * 1_073_741_824), optimizedTextRuntime: true)
            XCTAssertTrue(plan.fits); XCTAssertEqual(plan.selectedContextTokens, 65_536)
            XCTAssertEqual(plan.attentionCacheBits, bits)
            XCTAssertEqual(plan.fixedBytes, 2_367_118_848 + 256 * 1_024 * 1_024)
        }
    }
    func testHugeMemoryMeasurementsCannotOverflowOrBypassConfiguredCap() {
        let plan = LocalInferenceBudget(weightBytes: Int64.max, availableBytes: Int64.max, residentBytes: Int64.max, optimizedTextRuntime: true)
        XCTAssertFalse(plan.fits); XCTAssertEqual(plan.workingBytes, 8 * 1_073_741_824)
    }
}
