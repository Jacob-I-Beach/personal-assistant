import Foundation

public struct SleepInterval: Codable, Equatable, Sendable {
    public var start: Date
    public var end: Date
    public var source: String
    public init(start: Date, end: Date, source: String) { self.start = start; self.end = end; self.source = source }
}
public struct HealthDay: Codable, Identifiable, Equatable, Sendable {
    public var date: Date
    public var steps: Double?
    public var sleepHours: Double?
    public var id: Date { date }
    public init(date: Date, steps: Double?, sleepHours: Double?) { self.date = date; self.steps = steps; self.sleepHours = sleepHours }
}
public struct WorkoutRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var start: Date
    public var minutes: Double
    public var activity: String
    public var source: String
    public init(id: UUID, start: Date, minutes: Double, activity: String, source: String) {
        self.id = id; self.start = start; self.minutes = minutes; self.activity = activity; self.source = source
    }
}
public struct HealthOverview: Codable, Sendable {
    public var rangeStart: Date
    public var rangeEnd: Date
    public var timeZoneIdentifier: String
    public var days: [HealthDay]
    public var workouts: [WorkoutRecord]
    public var sleepSources: [String]
    public var source = "Apple HealthKit: user-authorized reads"
    public var coverageNote = "Missing data is not zero and does not establish denied permission. Results may cover only shared history. Sleep is unioned across overlapping asleep records and split by calendar day, not by night. Today's values are partial."
    public init(rangeStart: Date, rangeEnd: Date, calendar: Calendar, steps: [Date: Double], sleep: [SleepInterval], workouts: [WorkoutRecord]) {
        self.rangeStart = rangeStart; self.rangeEnd = rangeEnd; self.timeZoneIdentifier = calendar.timeZone.identifier
        self.workouts = workouts; self.sleepSources = Array(Set(sleep.map(\.source))).sorted()
        days = []
        var day = calendar.startOfDay(for: rangeStart)
        while day < rangeEnd, let next = calendar.date(byAdding: .day, value: 1, to: day), next > day, days.count < 31 {
            let start = max(day, rangeStart), end = min(next, rangeEnd)
            let clipped = sleep.filter { $0.start < end && $0.end > start }
            let duration = Self.unionDuration(clipped, from: start, to: end)
            let value = steps[day].flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
            days.append(HealthDay(date: day, steps: value, sleepHours: clipped.isEmpty ? nil : duration / 3600))
            day = next
        }
    }
    public static func unionDuration(_ intervals: [SleepInterval], from start: Date, to end: Date) -> TimeInterval {
        guard start < end else { return 0 }
        let ranges = intervals.compactMap { interval -> (Date, Date)? in
            let lower = max(start, interval.start), upper = min(end, interval.end)
            return lower < upper ? (lower, upper) : nil
        }.sorted { $0.0 < $1.0 }
        var total: TimeInterval = 0
        var active: (Date, Date)?
        for range in ranges {
            if let current = active {
                if range.0 <= current.1 { active = (current.0, max(current.1, range.1)) }
                else { total += current.1.timeIntervalSince(current.0); active = range }
            } else { active = range }
        }
        if let active { total += active.1.timeIntervalSince(active.0) }
        return total
    }
    public func discussionText() throws -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier); formatter.dateFormat = "yyyy-MM-dd"
        func number(_ value: Double?, decimals: Int) -> String {
            guard let value else { return "not shared" }
            return String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), decimals, value)
        }
        var lines = ["Selected Health overview (\(source)).", "Time zone: \(timeZoneIdentifier). Updated: \(ISO8601DateFormatter().string(from: rangeEnd)).",
                     "Date | Steps | Recorded sleep hours"]
        lines += days.map { "\(formatter.string(from: $0.date)) | \(number($0.steps, decimals: 0)) | \(number($0.sleepHours, decimals: 2))" }
        if workouts.isEmpty { lines.append("No workout records were shared for this period.") }
        else {
            lines.append("Latest \(min(workouts.count, 8)) of \(workouts.count) shared workouts:")
            lines += workouts.prefix(8).map { "\(formatter.string(from: $0.start)): \($0.activity), \(number($0.minutes, decimals: 1)) min; source: \($0.source)." }
        }
        if !sleepSources.isEmpty { lines.append("Sleep sources: " + sleepSources.joined(separator: ", ")) }
        lines.append(coverageNote)
        return "Help me understand this overview and plan my day. Cite dates and coverage, distinguish observations from interpretation, and use the calculated values below.\n\n" + lines.joined(separator: "\n")
    }
}
