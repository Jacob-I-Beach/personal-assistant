import Foundation

public struct HealthDataType: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let kind: String
    public let group: String
    public let source: String
}
public enum HealthDataCatalog {
    public static let entries: [HealthDataType] = {
        guard let url = Bundle.module.url(forResource: "HealthDataCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url), let entries = try? JSONDecoder().decode([HealthDataType].self, from: data) else { return [] }
        return entries.sorted { ($0.group, $0.name) < ($1.group, $1.name) }
    }()
    public static let initialSelection: Set<String> = ["HKQuantityTypeIdentifierStepCount", "HKCategoryTypeIdentifierSleepAnalysis", "workouts"]
    public static func matching(_ query: String) -> [HealthDataType] {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        return entries.filter { entry in terms.allSatisfy { (entry.name + " " + entry.group + " " + entry.id).lowercased().contains($0) } }
    }
}

/// A requested, bounded read. Permission and availability are checked again by
/// the device provider. A list of types contains schema, never private records.
public struct HealthDataQuery: Sendable {
    public let typeIDs: [String]
    public let start: Date
    public let end: Date
    public let mode: String
    public let limit: Int
    public init(typeIDs: [String], start: String, end: String, mode: String, limit: Int) throws {
        let allowed = Set(HealthDataCatalog.entries.map(\.id))
        func date(_ text: String) -> Date? {
            let formatter = ISO8601DateFormatter()
            if let value = formatter.date(from: text) { return value }
            formatter.formatOptions.insert(.withFractionalSeconds)
            return formatter.date(from: text)
        }
        guard (1...4).contains(typeIDs.count), Set(typeIDs).count == typeIDs.count, Set(typeIDs).isSubset(of: allowed),
              let from = date(start), let to = date(end), from < to, to.timeIntervalSince(from) <= 366 * 86_400,
              ["daily", "samples", "latest"].contains(mode), (1...200).contains(limit) else {
            throw AssistantError.invalidTool("Choose one to four listed Health types, an ISO-8601 date range of at most one year, daily/samples/latest mode and a limit from 1 to 200.")
        }
        self.typeIDs = typeIDs; self.start = from; self.end = to; self.mode = mode; self.limit = mode == "latest" ? 1 : limit
    }
}
