import AssistantCore
import XCTest
@testable import PersonalAssistant

@MainActor
final class HealthAndAttentionPlatformTests: XCTestCase {
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
