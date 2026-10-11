import AssistantCore
import Foundation
import EventKit
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
        XCTAssertFalse(settings.useComputer); XCTAssertNil(settings.companion); XCTAssertFalse(settings.contactsConnected)
    }
    func testRecurrenceCreatesNativeBoundedRulesAndRejectsConflictingEndings() throws {
        let value: JSONValue = .object(["frequency": .string("weekly"), "interval": .number(2), "count": .number(6), "until": .null])
        let rules = try PlanningRecurrence.rule(value)
        XCTAssertEqual(rules?.first?.frequency, .weekly); XCTAssertEqual(rules?.first?.interval, 2)
        XCTAssertEqual(rules?.first?.recurrenceEnd?.occurrenceCount, 6)
        XCTAssertThrowsError(try PlanningRecurrence.rule(.object(["frequency": .string("weekly"), "interval": .number(1), "count": .number(4), "until": .string("2026-12-01T12:00:00Z")])))
        XCTAssertTrue(try PlanningRecurrence.rule(.object(["frequency": .string("none")]))?.isEmpty == true)
        XCTAssertEqual(PlanningRecurrence.span(.object(["scope": .string("this_and_future")])), .futureEvents)
    }
    func testBatchSchemaUsesTypedChangesAndKeepsLegacyEventArgumentsCompatible() throws {
        let legacy: JSONValue = .object(["item_id": .string(""), "version": .string(""), "source_id": .string("fixture-calendar"), "title": .string("Example"), "start": .string("2026-11-01T12:00:00-05:00"), "end": .string("2026-11-01T13:00:00-05:00"), "location": .string(""), "notes": .string("")])
        let result = try ToolArguments.normalize(legacy, schema: PlanningTools.saveEvent.parameters)
        XCTAssertEqual(result["recurrence"], .null); XCTAssertEqual(result["all_day"], .null)
        let batch = try ToolArguments.normalize(.object(["changes": .array([.object(["operation": .string("save_calendar_event"), "arguments": legacy])])]), schema: PlanningBatchTools.apply.parameters)
        XCTAssertEqual(batch["changes"]?.arrayValue?.count, 1)
    }
}
