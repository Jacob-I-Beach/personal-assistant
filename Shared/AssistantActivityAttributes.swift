import ActivityKit
import Foundation

struct AssistantActivityAttributes: ActivityAttributes, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        var title: String
        var detail: String
        var phase: String
        var updatedAt: Date
        var steps: [String]? = nil
        var onComputer: Bool? = nil
        var finishedAt: Date? = nil
    }
    var conversationID: String
    var startedAt: Date
    var onComputer: Bool
    var modelName: String? = nil
}

extension AssistantActivityAttributes.ContentState {
    var isReady: Bool { phase == "ready" || phase == "completed" }
    var isWorking: Bool { phase == "working" }
    var isWaiting: Bool { phase == "waiting" }
    func headline(stale: Bool) -> String {
        if (stale && isWorking) || phase == "reconnecting" { return "Updating your progress" }
        return title
    }
    func supportingText(stale: Bool) -> String {
        if (stale && isWorking) || phase == "reconnecting" { return "Progress will sync when connected." }
        return detail
    }
}
