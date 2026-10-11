import Foundation

public struct ConversationSummary: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var updatedAt: Date
    public var messageCount: Int
    public var folderID: UUID?
    public var archivedAt: Date?
}

public struct ChatFolder: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var instructions: String
    public var createdAt: Date
    public init(id: UUID = UUID(), name: String, instructions: String = "") {
        self.id = id; self.name = name; self.instructions = instructions; self.createdAt = Date()
    }
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
    public var revision = 1
    public var id: UUID
    public var conversationID: UUID
    public var filename: String
    public var content: String
    public var createdAt: Date
    public var sourceCallID: String?
    public var previousRevisionID: UUID?
    public var containsLocalOnlyContext: Bool
    public var containsHealthData: Bool
    public init(id: UUID = UUID(), conversationID: UUID, filename: String, content: String,
                sourceCallID: String? = nil, previousRevisionID: UUID? = nil, containsLocalOnlyContext: Bool = false,
                containsHealthData: Bool = false) {
        self.id = id; self.conversationID = conversationID; self.filename = filename; self.content = content
        self.createdAt = Date(); self.sourceCallID = sourceCallID; self.previousRevisionID = previousRevisionID
        self.containsLocalOnlyContext = containsLocalOnlyContext; self.containsHealthData = containsHealthData
    }
    enum CodingKeys: String, CodingKey { case id, conversationID, filename, content, createdAt, sourceCallID, previousRevisionID, containsLocalOnlyContext, containsHealthData, revision }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); conversationID = try c.decode(UUID.self, forKey: .conversationID)
        filename = try c.decode(String.self, forKey: .filename); content = try c.decode(String.self, forKey: .content)
        createdAt = try c.decode(Date.self, forKey: .createdAt); sourceCallID = try c.decodeIfPresent(String.self, forKey: .sourceCallID)
        previousRevisionID = try c.decodeIfPresent(UUID.self, forKey: .previousRevisionID)
        containsLocalOnlyContext = try c.decodeIfPresent(Bool.self, forKey: .containsLocalOnlyContext) ?? false
        containsHealthData = try c.decodeIfPresent(Bool.self, forKey: .containsHealthData) ?? false
        revision = try c.decodeIfPresent(Int.self, forKey: .revision) ?? 1
    }
}
