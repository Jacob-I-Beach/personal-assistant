import ActivityKit
import Foundation

struct AssistantActivityAttributes: ActivityAttributes, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        var title: String
        var detail: String
        var phase: String
        var updatedAt: Date
    }
    var conversationID: String
    var startedAt: Date
    var onComputer: Bool
}
