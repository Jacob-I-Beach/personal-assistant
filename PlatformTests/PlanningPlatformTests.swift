import AssistantCore
import Foundation
import XCTest
@testable import PersonalAssistant

@MainActor
final class PlanningPlatformTests: XCTestCase {
    func testEventKitPrivacyDescriptionsAndBackgroundRegistrationAreBundled() {
        XCTAssertNotNil(Bundle.main.object(forInfoDictionaryKey: "NSCalendarsFullAccessUsageDescription"))
        XCTAssertNotNil(Bundle.main.object(forInfoDictionaryKey: "NSRemindersFullAccessUsageDescription"))
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String], [(Bundle.main.bundleIdentifier ?? "") + ".reply.*"])
    }
    func testPlanningDatesRequireAnOffsetAndCalendarVersionChangesAreRejected() throws {
        XCTAssertThrowsError(try PlanningService.date("tomorrow"))
        XCTAssertThrowsError(try PlanningService.date("2026-10-12T14:00:00"))
        XCTAssertEqual(try PlanningService.date("2026-10-12T14:00:00-04:00"), try PlanningService.date("2026-10-12T18:00:00Z"))
        let service = PlanningService(); service.installFixture()
        var settings = ModelSettings(); settings.calendarSourceIDs = ["fixture-calendar"]
        XCTAssertThrowsError(try service.validateChange(.object(["item_id": .string("fixture-event"), "source_id": .string("fixture-calendar"), "version": .string("old")]), kind: "calendar", settings: settings))
        let item = try service.validateChange(.object(["item_id": .string("fixture-event"), "source_id": .string("fixture-calendar"), "version": .string("v1")]), kind: "calendar", settings: settings)
        XCTAssertEqual(item?.title, "Example appointment")
    }
    func testPlanningSettingsMigrateWithoutSilentlyEnablingAccess() throws {
        let settings = try JSONDecoder().decode(ModelSettings.self, from: Data("{}".utf8))
        XCTAssertTrue(settings.calendarSourceIDs.isEmpty); XCTAssertTrue(settings.reminderSourceIDs.isEmpty)
        XCTAssertFalse(settings.planningConnectedAccess)
    }
}
