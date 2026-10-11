import Foundation

public struct PlanningSource: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let kind: String
    public let writable: Bool
    public init(id: String, title: String, kind: String, writable: Bool) { self.id = id; self.title = title; self.kind = kind; self.writable = writable }
}
public struct PlanningItem: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let sourceID: String
    public let sourceTitle: String
    public let kind: String
    public let title: String
    public let start: Date?
    public let end: Date?
    public let notes: String
    public let location: String
    public let completed: Bool
    public let allDay: Bool
    public let recurring: Bool
    public let version: String
    public let blocksTime: Bool
    public init(id: String, sourceID: String, sourceTitle: String, kind: String, title: String, start: Date?, end: Date?, notes: String, location: String = "", completed: Bool = false, allDay: Bool = false, recurring: Bool = false, version: String, blocksTime: Bool = true) {
        self.id = id; self.sourceID = sourceID; self.sourceTitle = sourceTitle; self.kind = kind; self.title = title
        self.start = start; self.end = end; self.notes = notes; self.location = location
        self.completed = completed; self.allDay = allDay; self.recurring = recurring; self.version = version; self.blocksTime = blocksTime
    }
    public var modelValue: JSONValue {
        .object(["item_id": .string(id), "source_id": .string(sourceID), "source": .string(sourceTitle), "kind": .string(kind), "title": .string(title),
            "start_or_due": start.map { .string(ISO8601DateFormatter().string(from: $0)) } ?? .null,
            "end": end.map { .string(ISO8601DateFormatter().string(from: $0)) } ?? .null,
            "notes": .string(String(notes.prefix(1600))), "location": .string(location), "completed": .bool(completed),
            "all_day": .bool(allDay), "blocks_time": .bool(blocksTime), "recurring": .bool(recurring), "version": .string(version)])
    }
}
public enum AvailabilityPlanner {
    /// Computes real gaps only inside requested local working hours. DST is handled by Calendar.
    public static func slots(start: Date, end: Date, minutes: Int, dayStart: Int, dayEnd: Int, timeZone: TimeZone, weekdaysOnly: Bool, busy: [DateInterval], limit: Int = 6) throws -> [DateInterval] {
        guard start < end, end.timeIntervalSince(start) <= 31 * 86_400, (5...480).contains(minutes),
              (0...23).contains(dayStart), (1...24).contains(dayEnd), dayStart < dayEnd else { throw AssistantError.invalidTool("Use a range up to 31 days, a duration of 5–480 minutes, and valid daily hours.") }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        var day = calendar.startOfDay(for: start), result: [DateInterval] = []
        let duration = Double(minutes) * 60
        while day < end, result.count < min(max(1, limit), 12) {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            defer { day = next }
            if weekdaysOnly && calendar.isDateInWeekend(day) { continue }
            guard let lower = calendar.date(bySettingHour: dayStart, minute: 0, second: 0, of: day),
                  let upper = dayEnd == 24 ? next : calendar.date(bySettingHour: dayEnd, minute: 0, second: 0, of: day) else { continue }
            let window = DateInterval(start: max(start, lower), end: max(max(start, lower), min(end, upper)))
            var cursor = window.start
            for block in busy.filter({ $0.end > window.start && $0.start < window.end }).sorted(by: { $0.start < $1.start }) {
                let boundary = min(window.end, block.start)
                if boundary.timeIntervalSince(cursor) >= duration, result.count < limit { result.append(DateInterval(start: cursor, duration: duration)) }
                cursor = max(cursor, block.end)
            }
            if window.end.timeIntervalSince(cursor) >= duration, result.count < limit { result.append(DateInterval(start: cursor, duration: duration)) }
        }
        return result
    }
}
