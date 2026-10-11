import AssistantCore
import Combine
import CryptoKit
@preconcurrency import EventKit
import Foundation
import UIKit

struct PlanningWriteUnverified: Error, LocalizedError {
    let itemID: String
    var errorDescription: String? { "The save was submitted, but the final item could not be verified. Read its current state before trying another change." }
}

@MainActor
final class PlanningService: ObservableObject {
    @Published private(set) var sources: [PlanningSource] = []
    @Published private(set) var today: [PlanningItem] = []
    @Published private(set) var homeNotice: String?
    private let events = EKEventStore()
    #if DEBUG
    private var fixtureItems: [PlanningItem]?
    func installFixture() {
        let start = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date())!
        sources = [.init(id: "fixture-calendar", title: "Example calendar", kind: "calendar", writable: true), .init(id: "fixture-reminders", title: "Example reminders", kind: "reminder", writable: true)]
        fixtureItems = [.init(id: "fixture-event", sourceID: "fixture-calendar", sourceTitle: "Example calendar", kind: "calendar", title: "Example appointment", start: start, end: start.addingTimeInterval(3600), notes: "Synthetic test data", version: "v1")]
    }
    #endif
    var calendarAuthorized: Bool {
        #if DEBUG
        if fixtureItems != nil { return true }
        #endif
        return EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }
    var remindersAuthorized: Bool {
        #if DEBUG
        if fixtureItems != nil { return true }
        #endif
        return EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }
    func connect(_ kind: String) async throws {
        guard UIApplication.shared.applicationState == .active else { throw AssistantError.invalidTool("Open the app to connect Calendar or Reminders.") }
        let granted: Bool
        if kind == "calendar" { granted = try await events.requestFullAccessToEvents() }
        else { granted = try await events.requestFullAccessToReminders() }
        guard granted else { throw AssistantError.invalidTool("Access was not granted. You can change it in iPhone Settings.") }
        refreshSources()
    }
    func refreshSources() {
        #if DEBUG
        if fixtureItems != nil { return }
        #endif
        sources = (calendarAuthorized ? events.calendars(for: .event).map { source($0, kind: "calendar") } : [])
            + (remindersAuthorized ? events.calendars(for: .reminder).map { source($0, kind: "reminder") } : [])
    }
    private func source(_ calendar: EKCalendar, kind: String) -> PlanningSource {
        .init(id: calendar.calendarIdentifier, title: calendar.title, kind: kind, writable: calendar.allowsContentModifications)
    }
    private func calendars(_ ids: [String], kind: String) throws -> [EKCalendar] {
        guard kind == "calendar" ? calendarAuthorized : remindersAuthorized else { throw AssistantError.invalidTool("Connect \(kind == "calendar" ? "Calendar" : "Reminders") in Planning access first.") }
        let allowed = events.calendars(for: kind == "calendar" ? .event : .reminder).filter { ids.contains($0.calendarIdentifier) }
        guard !allowed.isEmpty, Set(ids).isSubset(of: Set(allowed.map(\.calendarIdentifier))) else { throw AssistantError.invalidTool("Choose available calendars or reminder lists in Planning access. A previously selected source may have changed.") }
        return allowed
    }
    func schedule(from start: Date, to end: Date, sourceIDs: [String]) throws -> [PlanningItem] {
        try validateRange(start, end)
        #if DEBUG
        if let fixtureItems { return fixtureItems.filter { $0.kind == "calendar" && sourceIDs.contains($0.sourceID) && ($0.start ?? .distantFuture) < end && ($0.end ?? .distantPast) > start } }
        #endif
        let selected = try calendars(sourceIDs, kind: "calendar")
        return events.events(matching: events.predicateForEvents(withStart: start, end: end, calendars: selected))
            .filter { $0.status != .canceled }.sorted { $0.startDate < $1.startDate }.map(Self.snapshot)
    }
    func availability(from start: Date, to end: Date, minutes: Int, dayStart: Int, dayEnd: Int, timeZone: TimeZone, weekdaysOnly: Bool, sourceIDs: [String]) throws -> [DateInterval] {
        try validateRange(start, end)
        let selected = try calendars(sourceIDs, kind: "calendar")
        let values = events.events(matching: events.predicateForEvents(withStart: start, end: end, calendars: selected))
        guard values.count <= 1000 else { throw AssistantError.invalidTool("This range contains too many events to check completely. Use a shorter range.") }
        let busy = values.filter { $0.status != .canceled && $0.availability != .free && $0.startDate < $0.endDate }.map { DateInterval(start: $0.startDate, end: $0.endDate) }
        return try AvailabilityPlanner.slots(start: start, end: end, minutes: minutes, dayStart: dayStart, dayEnd: dayEnd, timeZone: timeZone, weekdaysOnly: weekdaysOnly, busy: busy)
    }
    func reminders(sourceIDs: [String], includeCompleted: Bool = false) async throws -> [PlanningItem] {
        #if DEBUG
        if let fixtureItems { return fixtureItems.filter { $0.kind == "reminder" && sourceIDs.contains($0.sourceID) && (includeCompleted || !$0.completed) } }
        #endif
        let selected = try calendars(sourceIDs, kind: "reminder")
        let predicate = events.predicateForReminders(in: selected)
        let values: [PlanningItem] = await withCheckedContinuation { continuation in
            events.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).filter { includeCompleted || !$0.isCompleted }.map(Self.snapshot))
            }
        }
        try Task.checkCancellation()
        return values.sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
    }
    func refreshHome(settings: ModelSettings) async {
        refreshSources()
        let calendar = Calendar.current, now = Date(), start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return }
        var result: [PlanningItem] = []; homeNotice = nil
        do {
            if !settings.calendarSourceIDs.isEmpty { result += try schedule(from: start, to: end, sourceIDs: settings.calendarSourceIDs) }
            if !settings.reminderSourceIDs.isEmpty { result += try await reminders(sourceIDs: settings.reminderSourceIDs).filter { $0.start.map { $0 < end } ?? false } }
            today = result.sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
        } catch { today = []; homeNotice = error.localizedDescription }
    }
    func readItem(id: String, kind: String, sourceIDs: [String]) throws -> PlanningItem {
        _ = try calendars(sourceIDs, kind: kind)
        let value: PlanningItem
        if kind == "calendar", let event = events.event(withIdentifier: id) { value = Self.snapshot(event) }
        else if kind == "reminder", let reminder = events.calendarItem(withIdentifier: id) as? EKReminder { value = Self.snapshot(reminder) }
        else { throw AssistantError.invalidTool("This item is no longer available. Read the current schedule or list again.") }
        guard sourceIDs.contains(value.sourceID) else { throw AssistantError.invalidTool("This item is outside your selected sources.") }
        return value
    }
    func validateChange(_ args: JSONValue, kind: String, settings: ModelSettings) throws -> PlanningItem? {
        let selected = kind == "calendar" ? settings.calendarSourceIDs : settings.reminderSourceIDs
        #if DEBUG
        if let fixtureItems {
            guard selected.contains(args["source_id"]?.stringValue ?? "fixture-reminders") else { throw AssistantError.invalidTool("Source is not selected") }
            let id = args["item_id"]?.stringValue ?? ""
            if id.isEmpty { return nil }
            guard let item = fixtureItems.first(where: { $0.id == id && $0.kind == kind && selected.contains($0.sourceID) }), item.version == args["version"]?.stringValue else { throw AssistantError.invalidTool("The item changed since it was read.") }
            return item
        }
        #endif
        let sources = try calendars(selected, kind: kind)
        let sourceID = args["source_id"]?.stringValue ?? ""
        if !sourceID.isEmpty { guard sources.contains(where: { $0.calendarIdentifier == sourceID && $0.allowsContentModifications }) else { throw AssistantError.invalidTool("Choose a writable source that you enabled in Planning access.") } }
        let id = args["item_id"]?.stringValue ?? ""
        guard !id.isEmpty else { guard !sourceID.isEmpty else { throw AssistantError.invalidTool("Choose a destination calendar or reminder list.") }; return nil }
        let item = try readItem(id: id, kind: kind, sourceIDs: selected)
        guard item.version == args["version"]?.stringValue else { throw AssistantError.invalidTool("The item changed since it was read. Refresh it and prepare a new review.") }
        guard !item.recurring, !item.allDay || kind == "reminder" else { throw AssistantError.invalidTool("Recurring and all-day events can be read; change their series or date handling in the native app.") }
        guard sources.contains(where: { $0.calendarIdentifier == item.sourceID && $0.allowsContentModifications }) else { throw AssistantError.invalidTool("This source is read-only.") }
        return item
    }
    func save(_ args: JSONValue, kind: String, settings: ModelSettings, completeOnly: Bool = false) throws -> PlanningItem {
        let existing = try validateChange(args, kind: kind, settings: settings)
        let sourceID = args["source_id"]?.stringValue ?? existing?.sourceID ?? ""
        let title = args["title"]?.stringValue ?? existing?.title ?? ""
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 300,
              (args["notes"]?.stringValue?.count ?? 0) <= 4000 else { throw AssistantError.invalidTool("Use a title up to 300 characters and notes up to 4,000 characters.") }
        #if DEBUG
        if fixtureItems != nil {
            let start = try (kind == "calendar" ? Self.date(args["start"]!.stringValue!) : (args["due"]?.stringValue).flatMap { $0.isEmpty ? nil : try Self.date($0) })
            let end = try kind == "calendar" ? Self.date(args["end"]!.stringValue!) : nil
            let item = PlanningItem(id: existing?.id ?? UUID().uuidString, sourceID: sourceID, sourceTitle: kind == "calendar" ? "Example calendar" : "Example reminders", kind: kind, title: title, start: start, end: end, notes: args["notes"]?.stringValue ?? "", completed: completeOnly, version: UUID().uuidString)
            fixtureItems?.removeAll { $0.id == item.id }; fixtureItems?.append(item); return item
        }
        #endif
        if kind == "calendar" {
            let start = try Self.date(args["start"]?.stringValue ?? ""), end = try Self.date(args["end"]?.stringValue ?? "")
            try validateRange(start, end)
            let event: EKEvent
            if let existing { guard let saved = events.event(withIdentifier: existing.id) else { throw AssistantError.invalidTool("The event disappeared. Read the schedule again.") }; event = saved }
            else { event = EKEvent(eventStore: events) }
            guard let calendar = events.calendar(withIdentifier: sourceID) else { throw AssistantError.invalidTool("The destination calendar is unavailable.") }
            event.calendar = calendar; event.title = title; event.startDate = start; event.endDate = end
            event.notes = args["notes"]?.stringValue; event.location = args["location"]?.stringValue
            try events.save(event, span: .thisEvent, commit: true)
            guard let id = event.eventIdentifier, let saved = events.event(withIdentifier: id), saved.title == title,
                  abs(saved.startDate.timeIntervalSince(start)) < 1, abs(saved.endDate.timeIntervalSince(end)) < 1,
                  saved.calendar.calendarIdentifier == sourceID else { throw PlanningWriteUnverified(itemID: event.eventIdentifier ?? event.calendarItemIdentifier) }
            return Self.snapshot(saved)
        }
        let reminder: EKReminder
        if let existing { guard let saved = events.calendarItem(withIdentifier: existing.id) as? EKReminder else { throw AssistantError.invalidTool("The reminder disappeared. Read the list again.") }; reminder = saved }
        else { reminder = EKReminder(eventStore: events) }
        if completeOnly {
            guard existing != nil else { throw AssistantError.invalidTool("Read the reminder before completing it.") }
            reminder.isCompleted = true
        } else {
            guard let calendar = events.calendar(withIdentifier: sourceID) else { throw AssistantError.invalidTool("The destination list is unavailable.") }
            reminder.calendar = calendar; reminder.title = title; reminder.notes = args["notes"]?.stringValue
            let raw = args["due"]?.stringValue ?? ""
            if raw.isEmpty { reminder.dueDateComponents = nil; reminder.alarms = nil }
            else {
                let date = try Self.date(raw)
                var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
                var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
                components.timeZone = calendar.timeZone; reminder.dueDateComponents = components
                reminder.alarms = [EKAlarm(absoluteDate: date)]
            }
        }
        try events.save(reminder, commit: true)
        guard let saved = events.calendarItem(withIdentifier: reminder.calendarItemIdentifier) as? EKReminder,
              saved.title == title, !completeOnly || saved.isCompleted else { throw PlanningWriteUnverified(itemID: reminder.calendarItemIdentifier) }
        if !completeOnly {
            let expectedDue = try (args["due"]?.stringValue).flatMap { $0.isEmpty ? nil : try Self.date($0) }
            let actual = Self.snapshot(saved)
            guard actual.sourceID == sourceID, actual.notes == (args["notes"]?.stringValue ?? ""),
                  (expectedDue == nil && actual.start == nil) || (expectedDue != nil && actual.start != nil && abs(actual.start!.timeIntervalSince(expectedDue!)) < 1) else { throw PlanningWriteUnverified(itemID: reminder.calendarItemIdentifier) }
        }
        return Self.snapshot(saved)
    }
    private func validateRange(_ start: Date, _ end: Date) throws {
        guard start < end, end.timeIntervalSince(start) <= 31 * 86_400 else { throw AssistantError.invalidTool("Choose a valid date range of at most 31 days.") }
    }
    static func date(_ raw: String) throws -> Date {
        guard raw.contains("T"), let date = ISO8601DateFormatter().date(from: raw) else { throw AssistantError.invalidTool("Use an ISO8601 date and time including its time-zone offset.") }
        return date
    }
    private nonisolated static func fingerprint(_ values: [String]) -> String { SHA256.hash(data: Data(values.joined(separator: "\u{0}").utf8)).map { String(format: "%02x", $0) }.joined() }
    private nonisolated static func snapshot(_ event: EKEvent) -> PlanningItem {
        let version = fingerprint([event.eventIdentifier ?? "", event.title ?? "", event.startDate.description, event.endDate.description, event.notes ?? "", event.location ?? "", event.calendar.calendarIdentifier, event.lastModifiedDate?.description ?? "", String(event.isAllDay), String(event.availability.rawValue)])
        return .init(id: event.eventIdentifier ?? event.calendarItemIdentifier, sourceID: event.calendar.calendarIdentifier, sourceTitle: event.calendar.title, kind: "calendar", title: event.title ?? "Untitled event", start: event.startDate, end: event.endDate, notes: event.notes ?? "", location: event.location ?? "", allDay: event.isAllDay, recurring: event.hasRecurrenceRules || event.isDetached, version: version, blocksTime: event.availability != .free)
    }
    private nonisolated static func snapshot(_ reminder: EKReminder) -> PlanningItem {
        var calendar = Calendar.current; calendar.timeZone = reminder.dueDateComponents?.timeZone ?? .current
        let due = reminder.dueDateComponents.flatMap { calendar.date(from: $0) }
        let version = fingerprint([reminder.calendarItemIdentifier, reminder.title ?? "", due?.description ?? "", reminder.notes ?? "", String(reminder.isCompleted), reminder.calendar.calendarIdentifier, reminder.lastModifiedDate?.description ?? ""])
        return .init(id: reminder.calendarItemIdentifier, sourceID: reminder.calendar.calendarIdentifier, sourceTitle: reminder.calendar.title, kind: "reminder", title: reminder.title ?? "Untitled reminder", start: due, end: nil, notes: reminder.notes ?? "", completed: reminder.isCompleted, allDay: reminder.dueDateComponents?.hour == nil, recurring: reminder.hasRecurrenceRules, version: version)
    }
}

enum PlanningTools {
    static let sources = NativeTools.definition("list_planning_sources", "List the calendars and reminder lists the user enabled for this assistant. Does not grant access to unselected sources.", [:])
    static let schedule = NativeTools.definition("read_schedule", "Read events in all enabled calendars for a bounded time range. Reports all-day events and time-zone-aware dates. Results are capped; use shorter ranges if coverage is partial.", ["start": "ISO8601 date-time with offset", "end": "ISO8601 date-time with offset, at most 31 days later"])
    static let available = NativeTools.definition("find_available_time", "Find conflict-free slots in selected calendars, within requested local daily hours. Does not inspect other people's calendars or estimate travel time. Assumes tentative/busy events block time.", ["start": "Start ISO8601 with offset", "end": "End ISO8601, at most 31 days later", "minutes": "Required duration 5–480", "day_start_hour": "Local start hour 0–23", "day_end_hour": "Local end hour 1–24", "time_zone": "IANA name, such as America/New_York", "weekdays_only": "true or false"])
    static let reminders = NativeTools.definition("read_reminders", "Read current unfinished reminders in selected lists, including due times. Does not read unselected lists.", ["query": "Optional words in the title; empty for all unfinished reminders"])
    static let saveEvent = NativeTools.definition("save_calendar_event", "Create or update a timed, nonrecurring event after exact native review, then read it back. Existing items require the version returned by read_schedule. Recheck availability before proposing a time. A cancelled review performs no save.", ["item_id": "Empty for new; returned item_id for existing", "version": "Empty for new; exact returned version for existing", "source_id": "Writable enabled calendar ID", "title": "Title", "start": "ISO8601 date-time with offset", "end": "ISO8601 date-time with offset", "location": "Location, or empty", "notes": "Notes, or empty"])
    static let saveReminder = NativeTools.definition("save_reminder", "Create or update a nonrecurring reminder after review, then read it back. A due time also sets its reminder alarm. Use the returned version for updates. This schedules a reminder notification, not a future model run.", ["item_id": "Empty for new; returned item_id for existing", "version": "Empty for new; returned version for existing", "source_id": "Writable enabled reminder-list ID", "title": "Title", "due": "ISO8601 date-time with offset, or empty for no due time", "notes": "Notes, or empty"])
    static let complete = NativeTools.definition("complete_reminder", "Mark one previously read, nonrecurring reminder complete after review and verify the result. Does not delete it.", ["item_id": "Returned reminder ID", "version": "Exact current version"])
    static let definitions = [sources, schedule, available, reminders, saveEvent, saveReminder, complete]
    static let names = Set(definitions.map(\.name))
}
