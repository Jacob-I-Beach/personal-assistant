import AssistantCore
import CryptoKit
@preconcurrency import EventKit
import Foundation

/// Converts EventKit objects on the queue that delivered them. Only immutable,
/// Sendable snapshots cross back to PlanningService's main-actor state.
enum PlanningEventKitBridge {
    nonisolated static func reminderCompletion(
        includeCompleted: Bool,
        continuation: CheckedContinuation<[PlanningItem], any Error>
    ) -> @Sendable ([EKReminder]?) -> Void {
        // EventKit's Objective-C completion has no actor annotation. Creating an
        // ordinary closure in PlanningService inherited MainActor and trapped
        // when EventKit invoked it on com.apple.eventkit.reminders.search.
        { @Sendable reminders in
            do {
                guard let reminders else {
                    throw AssistantError.invalidTool("Reminders did not return a result. Try refreshing your selected lists.")
                }
                let items = try reminders.filter { includeCompleted || !$0.isCompleted }.map(snapshot)
                continuation.resume(returning: items)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    nonisolated static func snapshot(_ event: EKEvent) throws -> PlanningItem {
        let id = event.eventIdentifier ?? event.calendarItemIdentifier
        guard let calendar = event.calendar, !calendar.calendarIdentifier.isEmpty, !id.isEmpty,
              let start = event.startDate, let end = event.endDate, start <= end else {
            throw AssistantError.invalidTool("A calendar event is temporarily incomplete. Refresh Calendar and try again; availability has not been confirmed.")
        }
        let sourceID = calendar.calendarIdentifier
        let version = fingerprint([id, event.title ?? "", start.description, end.description, event.notes ?? "", event.location ?? "", sourceID, event.lastModifiedDate?.description ?? "", String(event.isAllDay), String(event.availability.rawValue)])
        return .init(id: id, sourceID: sourceID, sourceTitle: calendar.title, kind: "calendar", title: event.title ?? "Untitled event", start: start, end: end, notes: event.notes ?? "", location: event.location ?? "", allDay: event.isAllDay, recurring: event.hasRecurrenceRules || event.isDetached, version: version, blocksTime: event.availability != .free)
    }

    nonisolated static func snapshot(_ reminder: EKReminder) throws -> PlanningItem {
        let id = reminder.calendarItemIdentifier
        guard let calendar = reminder.calendar, !calendar.calendarIdentifier.isEmpty, !id.isEmpty else {
            throw AssistantError.invalidTool("A reminder is temporarily incomplete. Refresh Reminders and try reading the list again.")
        }
        let sourceID = calendar.calendarIdentifier
        var dateCalendar = reminder.dueDateComponents?.calendar ?? Calendar.current
        dateCalendar.timeZone = reminder.dueDateComponents?.timeZone ?? .current
        let due = reminder.dueDateComponents.flatMap { dateCalendar.date(from: $0) }
        if reminder.dueDateComponents != nil && due == nil {
            throw AssistantError.invalidTool("A reminder has an unreadable due date. Check it in Reminders and refresh this list.")
        }
        let version = fingerprint([id, reminder.title ?? "", due?.description ?? "", reminder.notes ?? "", String(reminder.isCompleted), sourceID, reminder.lastModifiedDate?.description ?? ""])
        return .init(id: id, sourceID: sourceID, sourceTitle: calendar.title, kind: "reminder", title: reminder.title ?? "Untitled reminder", start: due, end: nil, notes: reminder.notes ?? "", completed: reminder.isCompleted, allDay: reminder.dueDateComponents?.hour == nil, recurring: reminder.hasRecurrenceRules, version: version)
    }

    private nonisolated static func fingerprint(_ values: [String]) -> String {
        SHA256.hash(data: Data(values.joined(separator: "\u{0}").utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
