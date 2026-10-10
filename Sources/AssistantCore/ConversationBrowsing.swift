import Foundation

extension LocalStore {
    public func browsableConversations(remote: Bool, query: String = "", offset: Int = 0, limit: Int = 12) throws -> [ConversationSummary] {
        guard (0...100_000).contains(offset), query.utf8.count <= 300 else { throw AssistantError.invalidTool("Use a short title query and a valid page offset.") }
        let protected = remote ? " AND COALESCE(json_extract(CAST(c.payload AS TEXT),'$.networkDisabled'),0)=0 AND NOT EXISTS(SELECT 1 FROM messages p WHERE p.conversation_id=c.id AND (COALESCE(json_extract(CAST(p.payload AS TEXT),'$.containsLocalOnlyContext'),0)=1 OR COALESCE(json_extract(CAST(p.payload AS TEXT),'$.containsHealthData'),0)=1))" : ""
        let title = "COALESCE(json_extract(CAST(c.payload AS TEXT),'$.modelTitleOverride'),c.title)"
        return try database.execute("""
            SELECT c.payload, (SELECT COUNT(*) FROM messages m WHERE m.conversation_id=c.id), \(title)
            FROM conversations c WHERE json_extract(CAST(c.payload AS TEXT),'$.archivedAt') IS NULL
            AND instr(lower(\(title)),lower(?))>0 \(protected)
            ORDER BY c.updated_at DESC, c.id LIMIT ? OFFSET ?
            """, [.text(query), .integer(Int64(min(max(limit, 1), 20))), .integer(Int64(offset))]).map { row in
                let value = try Self.decode(Conversation.self, row[0].data!)
                return ConversationSummary(id: value.id, title: row[2].text!, updatedAt: value.updatedAt, messageCount: Int(row[1].number ?? 0), folderID: value.folderID, archivedAt: nil)
            }
    }
    public func browseConversationMessages(_ id: UUID, remote: Bool, offset: Int = 0, limit: Int = 12) throws -> [Message] {
        guard (0...100_000).contains(offset) else { throw AssistantError.invalidTool("Invalid history page offset.") }
        let chat = try loadConversation(id)
        guard chat.archivedAt == nil, !remote || (!chat.networkDisabled && !chat.messages.contains(where: { $0.containsLocalOnlyContext || $0.containsHealthData })) else {
            throw AssistantError.invalidTool("This conversation is outside the permitted history scope.")
        }
        return Array(chat.messages.reversed().dropFirst(offset).prefix(min(max(limit, 1), 20)).reversed())
    }
}
