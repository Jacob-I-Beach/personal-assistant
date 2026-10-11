import AssistantCore
@preconcurrency import EventKit
import Foundation
import XCTest
#if SWIFT_PACKAGE
@testable import PlanningEventKitBridge
#else
@testable import PersonalAssistant
#endif

final class PlanningEventKitBridgeTests: XCTestCase, @unchecked Sendable {
    @MainActor
    func testReminderCompletionCanReturnOnEventKitBackgroundQueue() async throws {
        // Start on MainActor, like Save/launch, but deliver on EventKit's kind of
        // queue. A closure that inherits MainActor traps before reading results.
        let values: [PlanningItem] = try await withCheckedThrowingContinuation { continuation in
            let completion = PlanningEventKitBridge.reminderCompletion(includeCompleted: false, continuation: continuation)
            DispatchQueue(label: "test.eventkit.reminders.search").async {
                dispatchPrecondition(condition: .notOnQueue(.main))
                completion([])
            }
        }
        MainActor.assertIsolated()
        XCTAssertEqual(values, [])
    }

    func testOverlappingLaunchAndSaveFetchesFinishIndependently() async throws {
        try await withThrowingTaskGroup(of: [PlanningItem].self) { group in
            for _ in 0..<32 {
                group.addTask {
                    try await withCheckedThrowingContinuation { continuation in
                        let completion = PlanningEventKitBridge.reminderCompletion(includeCompleted: false, continuation: continuation)
                        DispatchQueue.global(qos: .userInitiated).async { completion([]) }
                    }
                }
            }
            var finished = 0
            for try await values in group { XCTAssertTrue(values.isEmpty); finished += 1 }
            XCTAssertEqual(finished, 32)
        }
    }

    func testMissingFetchResultReturnsAnErrorWithoutCrashing() async {
        do {
            let _: [PlanningItem] = try await withCheckedThrowingContinuation { continuation in
                let completion = PlanningEventKitBridge.reminderCompletion(includeCompleted: false, continuation: continuation)
                DispatchQueue.global().async { completion(nil) }
            }
            XCTFail("An absent fetch result must not be reported as an empty list.")
        } catch { XCTAssertTrue(error.localizedDescription.contains("did not return a result")) }
    }

    func testIncompleteReminderReturnsAnErrorFromBackgroundQueue() async {
        do {
            let _: [PlanningItem] = try await withCheckedThrowingContinuation { continuation in
                let completion = PlanningEventKitBridge.reminderCompletion(includeCompleted: false, continuation: continuation)
                DispatchQueue.global().async {
                    let reminder = EKReminder(eventStore: EKEventStore())
                    reminder.title = "Unsaved test reminder" // No calendar assigned.
                    completion([reminder])
                }
            }
            XCTFail("An incomplete item must not crash or silently disappear.")
        } catch { XCTAssertTrue(error.localizedDescription.contains("incomplete")) }
    }

    func testReminderSnapshotsKeepDueDatesAndFilterCompletedItems() async throws {
        let values: [PlanningItem] = try await withCheckedThrowingContinuation { continuation in
            let completion = PlanningEventKitBridge.reminderCompletion(includeCompleted: false, continuation: continuation)
            DispatchQueue.global().async {
                let store = EKEventStore()
                let list = EKCalendar(for: .reminder, eventStore: store)
                list.title = "Synthetic reminders"
                let open = EKReminder(eventStore: store)
                open.title = "Synthetic open task"; open.calendar = list
                open.dueDateComponents = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(secondsFromGMT: 0), year: 2026, month: 10, day: 12, hour: 14, minute: 30)
                let done = EKReminder(eventStore: store)
                done.title = "Synthetic completed task"; done.calendar = list; done.isCompleted = true
                completion([open, done])
            }
        }
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values.first?.title, "Synthetic open task")
        XCTAssertEqual(values.first?.sourceTitle, "Synthetic reminders")
        XCTAssertEqual(values.first?.start, ISO8601DateFormatter().date(from: "2026-10-12T14:30:00Z"))
        XCTAssertFalse(values.first?.allDay ?? true)
    }

    func testUndatedReminderAndCompletionArePreservedWhenRequested() async throws {
        let values: [PlanningItem] = try await withCheckedThrowingContinuation { continuation in
            let completion = PlanningEventKitBridge.reminderCompletion(includeCompleted: true, continuation: continuation)
            DispatchQueue.global().async {
                let store = EKEventStore()
                let list = EKCalendar(for: .reminder, eventStore: store); list.title = "Synthetic list"
                let reminder = EKReminder(eventStore: store)
                reminder.calendar = list; reminder.title = "Completed without a due date"; reminder.isCompleted = true
                completion([reminder])
            }
        }
        XCTAssertEqual(values.count, 1)
        XCTAssertNil(values.first?.start)
        XCTAssertTrue(values.first?.completed ?? false)
    }

    func testIncompleteEventsRejectWithoutClaimingAvailability() throws {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        XCTAssertThrowsError(try PlanningEventKitBridge.snapshot(event))
        event.calendar = EKCalendar(for: .event, eventStore: store)
        XCTAssertThrowsError(try PlanningEventKitBridge.snapshot(event))
        event.startDate = Date(timeIntervalSince1970: 1000)
        event.endDate = Date(timeIntervalSince1970: 900)
        XCTAssertThrowsError(try PlanningEventKitBridge.snapshot(event))
    }

    func testValidEventSnapshotPreservesVersionAndBusyState() throws {
        let store = EKEventStore()
        let calendar = EKCalendar(for: .event, eventStore: store); calendar.title = "Synthetic calendar"
        let event = EKEvent(eventStore: store); event.calendar = calendar; event.title = "Synthetic appointment"
        event.startDate = Date(timeIntervalSince1970: 1000); event.endDate = Date(timeIntervalSince1970: 4600)
        let before = try PlanningEventKitBridge.snapshot(event)
        XCTAssertEqual(before.start, event.startDate); XCTAssertEqual(before.end, event.endDate)
        XCTAssertEqual(before.sourceTitle, "Synthetic calendar"); XCTAssertTrue(before.blocksTime)
        event.title = "Updated synthetic appointment"
        XCTAssertNotEqual(try PlanningEventKitBridge.snapshot(event).version, before.version)
    }
}
