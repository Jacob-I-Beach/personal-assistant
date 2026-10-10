import Foundation

public enum ReasoningEffort: String, Codable, CaseIterable, Sendable, Identifiable {
    case low, medium, high, xhigh, max
    public var id: String { rawValue }
    public var title: String {
        switch self { case .low: "Low"; case .medium: "Medium"; case .high: "High"; case .xhigh: "Extra High"; case .max: "Max" }
    }
    public var summary: String {
        switch self {
        case .low: "Quicker responses for straightforward work."
        case .medium: "A balance of speed and depth."
        case .high: "More time for complex questions and tasks."
        case .xhigh: "Extra effort for difficult analysis."
        case .max: "The highest supported effort; can take longer and use more of your allowance."
        }
    }
    public static func documented(for model: String) -> [Self] {
        let names = ["gpt-6.1-sol", "gpt-6-astra", "gpt-6-sol", "gpt-6-luna"]
        return names.contains(model.lowercased()) ? allCases : []
    }
}
