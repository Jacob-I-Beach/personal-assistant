import AssistantCore
import HealthKit
import XCTest
@testable import PersonalAssistant

@MainActor
final class HealthAndAttentionPlatformTests: XCTestCase {
    func testSelectAllAuthorizationUsesComponentsAndSeparatesRecordPickers() {
        let plan = HealthAuthorizationPlan(selected: Set(HealthDataCatalog.entries.map(\.id)))
        XCTAssertFalse(plan.ordinary.contains { $0 is HKCorrelationType })
        XCTAssertFalse(plan.ordinary.contains { $0.requiresPerObjectAuthorization() })
        XCTAssertTrue(plan.ordinary.contains(HKQuantityType(.bloodPressureSystolic)))
        XCTAssertTrue(plan.ordinary.contains(HKQuantityType(.bloodPressureDiastolic)))
        let pressure = HealthAuthorizationPlan(selected: ["HKCorrelationTypeIdentifierBloodPressure"])
        XCTAssertEqual(Set(pressure.ordinary.map(\.identifier)), ["HKQuantityTypeIdentifierBloodPressureSystolic", "HKQuantityTypeIdentifierBloodPressureDiastolic"])
        let food = HealthAuthorizationPlan(selected: ["HKCorrelationTypeIdentifierFood"])
        XCTAssertTrue(food.ordinary.contains(HKQuantityType(.dietaryEnergyConsumed)))
        XCTAssertFalse(food.ordinary.contains { $0 is HKCorrelationType })
    }
    func testFrameworkValidationExceptionBecomesARecoverableError() {
        XCTAssertThrowsError(try HealthFrameworkBoundary.perform {
            NSException(name: .invalidArgumentException, reason: "Synthetic invalid authorization input", userInfo: nil).raise()
        }) { error in
            XCTAssertEqual((error as NSError).domain, "Assistant.FrameworkValidation")
        }
    }
    func testNotificationCompletionRunsOnMainThreadAndOnlyOnce() async {
        var calls = 0
        let completion = MainThreadNotificationCompletion<Int> { value in
            XCTAssertTrue(Thread.isMainThread); XCTAssertEqual(value, 1); calls += 1
        }
        await Task.detached {
            await completion.finish(1)
            await completion.finish(2)
        }.value
        XCTAssertEqual(calls, 1)
    }
    func testHealthPercentagesAreNotReportedAsFractionsWithPercentLabels() {
        XCTAssertEqual(HealthDataReader.readableValue(HKQuantity(unit: .percent(), doubleValue: 0.98), unit: .percent()), 98, accuracy: 0.0001)
        XCTAssertEqual(HealthDataReader.readableValue(HKQuantity(unit: .count(), doubleValue: 3000), unit: .count()), 3000)
    }
    func testHealthCatalogResolvesSDKTypesAndDoesNotClaimClinicalEntitlements() throws {
        let available = HealthDataCatalog.entries.filter { HealthDataReader.objectType($0) != nil }
        XCTAssertGreaterThan(available.count, 190)
        XCTAssertTrue(available.contains { $0.id == "medications" })
        XCTAssertTrue(available.contains { $0.id == "HKQuantityTypeIdentifierHeartRate" })
        XCTAssertFalse(HealthDataReader.hasClinicalAccess)
        XCTAssertFalse(available.contains { $0.kind == "clinical" })
        let catalog = HealthDataReader.catalog(query: "heart rate", selected: ["HKQuantityTypeIdentifierHeartRate"])
        XCTAssertTrue(catalog["types"]?.arrayValue?.contains { $0["selected_in_app"] == .bool(true) } == true)
        XCTAssertNil(catalog["records"])
        print("Available Health type schemas: \(available.count); unavailable: \(HealthDataCatalog.entries.filter { HealthDataReader.objectType($0) == nil }.map(\.id))")
    }
    func testAttentionEndsProcessingNormallyAndReturnRouteIsOneShot() {
        let turn = UUID(), chat = UUID()
        let window = ResponseCompletionWindow()
        window.begin { _ in XCTFail("A planned question is not an expiration") }
        window.identifyTurn(turn); window.received(bytes: 128)
        window.waitingForAttention(question: true)
        XCTAssertEqual(ResponseCompletionWindow.diagnostic(for: turn)["state"], .string("waiting_for_answer"))
        ReplyReturnRoute.remember(chat)
        XCTAssertEqual(ReplyReturnRoute.take(), chat); XCTAssertNil(ReplyReturnRoute.take())
    }
}
