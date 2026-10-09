import Foundation

public struct ConversationSummary: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var updatedAt: Date
    public var messageCount: Int
}
public struct HistoryMatch: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var conversationID: UUID
    public var title: String
    public var excerpt: String
    public var role: MessageRole
    public var createdAt: Date
}
public struct ArtifactRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var conversationID: UUID
    public var filename: String
    public var content: String
    public var createdAt: Date
    public var sourceCallID: String?
    public var previousRevisionID: UUID?
    public init(id: UUID = UUID(), conversationID: UUID, filename: String, content: String,
                sourceCallID: String? = nil, previousRevisionID: UUID? = nil) {
        self.id = id; self.conversationID = conversationID; self.filename = filename; self.content = content
        self.createdAt = Date(); self.sourceCallID = sourceCallID; self.previousRevisionID = previousRevisionID
    }
}
