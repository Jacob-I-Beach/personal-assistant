import Foundation

public struct HistoryLanding: Equatable, Sendable, Identifiable {
    public let id = UUID()
    public var conversationID: UUID
    public var messageID: UUID
    public var anchorID: UUID
    public var lowerBound: Int
    public var upperBound: Int
    /// Navigation-only change detection; never an authorization or write token.
    public static func fingerprint(_ text: String) -> String {
        var value: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 { value = (value ^ UInt64(byte)) &* 1_099_511_628_211 }
        return "\(text.utf8.count):" + String(value, radix: 16)
    }
    public init(match: HistoryMatch, conversation: Conversation) throws {
        guard match.conversationID == conversation.id, let message = conversation.messages.first(where: { $0.id == match.id }) else { throw AssistantError.provider("That search result is no longer available. Search again for the current conversation.") }
        if let signature = match.sourceFingerprint, signature != Self.fingerprint(message.text) { throw AssistantError.provider("That message changed after the search. Search again to open its current text.") }
        let timeline = ChatTimeline.items(conversation.messages)
        guard let index = timeline.firstIndex(where: { $0.messages.contains(where: { $0.id == match.id }) }) else { throw AssistantError.provider("The matched message no longer has visible content.") }
        conversationID = conversation.id; messageID = match.id; anchorID = timeline[index].id
        lowerBound = max(0, index - 20); upperBound = min(timeline.count, lowerBound + 100)
    }
}
