import Foundation

public struct ContextLimits: Sendable {
    /// Conservative UTF-8 text budget, not a claim of exact token counting. Backends can lower it further.
    public var maximumTextBytes: Int
    public var maximumImages: Int
    public init(maximumTextBytes: Int = 32_768, maximumImages: Int = 2) {
        self.maximumTextBytes = maximumTextBytes; self.maximumImages = maximumImages
    }
}
public struct ContextSelection: Sendable {
    public var messages: [Message]
    public var omittedMessageCount: Int
    public var imageCaptureIDs: Set<UUID>
}
public enum ContextPlanner {
    public static func select(_ messages: [Message], instructions: String, tools: [ToolDefinition], limits: ContextLimits) throws -> ContextSelection {
        let toolBytes = try tools.reduce(0) { $0 + $1.name.utf8.count + $1.description.utf8.count + (try $1.parameters.jsonString()).utf8.count + 100 }
        let budget = limits.maximumTextBytes - instructions.utf8.count - toolBytes - 2048
        guard budget > 0 else { throw AssistantError.provider("The selected model cannot fit these tools. Choose a model with more context.") }
        var turns: [[Message]] = []
        for message in messages {
            if message.role == .user || turns.isEmpty { turns.append([]) }
            turns[turns.count - 1].append(message)
        }
        var chosen: [[Message]] = [], used = 0
        for turn in turns.reversed() {
            let size = try turn.reduce(0) { sum, message in
                let calls = try message.toolCalls.reduce(0) { $0 + $1.name.utf8.count + (try $1.arguments.jsonString()).utf8.count + 100 }
                let opaque = try message.continuation?.items.reduce(0) { $0 + (try $1.jsonString()).utf8.count } ?? 0
                return sum + message.text.utf8.count + calls + opaque + message.captureIDs.count * 200 + 100
            }
            if used + size > budget {
                if chosen.isEmpty { throw AssistantError.provider("The latest request and its tool results exceed this model's working context. The complete conversation is saved; shorten the request or choose a model with more context.") }
                break
            }
            chosen.append(turn); used += size
        }
        let selected = chosen.reversed().flatMap { $0 }
        var seen = Set<UUID>()
        let images = selected.reversed().flatMap(\.captureIDs).filter { seen.insert($0).inserted }.prefix(max(0, limits.maximumImages))
        return ContextSelection(messages: selected, omittedMessageCount: messages.count - selected.count, imageCaptureIDs: Set(images))
    }
}
