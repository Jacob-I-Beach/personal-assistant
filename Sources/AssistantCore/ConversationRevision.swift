import Foundation

/// A local transcript branch, including the output versions visible at that time.
/// It is never a task queue or permission to repeat an external action.
public struct ConversationRevision: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let reason: String
    public let conversation: Conversation
    public let artifacts: [ArtifactRecord]
    public let surfaces: [WorkSurface]
}

extension LocalStore {
    func prepareConversationRevisions() throws { try Self.prepareRevisionStorage(database) }
    static func prepareRevisionStorage(_ database: SQLiteDatabase) throws {
        try database.execute("CREATE TABLE IF NOT EXISTS conversation_revisions(id TEXT PRIMARY KEY,conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,created_at REAL NOT NULL,payload BLOB NOT NULL,contains_health INTEGER NOT NULL DEFAULT 0)")
        let columns = try database.execute("PRAGMA table_info(conversation_revisions)").compactMap { $0[1].text }
        if !columns.contains("contains_health") {
            try database.transaction {
                try database.execute("ALTER TABLE conversation_revisions ADD COLUMN contains_health INTEGER NOT NULL DEFAULT 0")
                try database.execute("UPDATE conversation_revisions SET contains_health=EXISTS(SELECT 1 FROM json_tree(CAST(payload AS TEXT)) WHERE key='containsHealthData' AND type='true')")
            }
        }
        try database.execute("CREATE INDEX IF NOT EXISTS conversation_revision_order ON conversation_revisions(conversation_id,created_at)")
        try database.execute("CREATE INDEX IF NOT EXISTS conversation_revision_health ON conversation_revisions(contains_health)")
        for action in ["INSERT", "UPDATE OF payload"] {
            let name = action == "INSERT" ? "insert" : "update"
            try database.execute("CREATE TRIGGER IF NOT EXISTS revision_health_\(name) AFTER \(action) ON conversation_revisions BEGIN UPDATE conversation_revisions SET contains_health=EXISTS(SELECT 1 FROM json_tree(CAST(new.payload AS TEXT)) WHERE key='containsHealthData' AND type='true') WHERE id=new.id; END")
        }
    }
    func makeConversationRevision(_ chat: Conversation, reason: String) throws -> ConversationRevision {
        ConversationRevision(id: UUID(), createdAt: Date(), reason: reason, conversation: chat,
            artifacts: try artifacts(conversationID: chat.id).filter { !chat.excludedArtifactIDs.contains($0.id) },
            surfaces: try surfaces(conversationID: chat.id).filter { !chat.excludedSurfaceIDs.contains($0.id) })
    }
    func insertConversationRevision(_ value: ConversationRevision) throws {
        try database.execute("INSERT INTO conversation_revisions(id,conversation_id,created_at,payload) VALUES(?,?,?,?)", [.text(value.id.uuidString), .text(value.conversation.id.uuidString), .real(value.createdAt.timeIntervalSince1970), .blob(try Self.encode(value))])
    }
    public func conversationRevisions(_ conversationID: UUID) throws -> [ConversationRevision] {
        try prepareConversationRevisions()
        return try database.execute("SELECT payload FROM conversation_revisions WHERE conversation_id=? ORDER BY created_at DESC", [.text(conversationID.uuidString)])
            .map { try Self.decode(ConversationRevision.self, $0[0].data!) }
    }
    public func restoreConversationRevision(_ revisionID: UUID, expected: Conversation) throws -> Conversation {
        try prepareConversationRevisions()
        let current = try loadConversation(expected.id, preservingStreaming: true)
        guard current == expected,
              let revision = try conversationRevisions(current.id).first(where: { $0.id == revisionID }) else {
            throw AssistantError.invalidTool("The conversation changed. Reopen its history before restoring it.")
        }
        let work = try unfinishedWork()
        guard !work.contains(where: { $0.conversationID == current.id && $0.phase == .running }) else {
            throw AssistantError.invalidTool("Finish or stop this conversation's task before restoring its transcript.")
        }
        let displaced = try makeConversationRevision(current, reason: "Before restoring an earlier transcript")
        var restored = revision.conversation
        // Revocation, protected context and invalidated outputs do not roll back.
        restored.networkDisabled = current.networkDisabled
        restored.allowedNetworkDestinations = current.allowedNetworkDestinations
        restored.allowedHealthDestinations = current.allowedHealthDestinations
        restored.requiresNetworkReview = current.requiresNetworkReview
        restored.folderID = current.folderID
        restored.workspaceIDs = current.workspaceIDs
        restored.archivedAt = current.archivedAt
        if !current.titleWasGenerated { restored.title = current.title; restored.titleWasGenerated = false; restored.needsAutomaticTitle = current.needsAutomaticTitle }
        restored.excludedArtifactIDs.formUnion(current.excludedArtifactIDs)
        restored.excludedSurfaceIDs.formUnion(current.excludedSurfaceIDs)
        restored.excludedFileIDs.formUnion(current.excludedFileIDs)
        restored.invalidatedProjectRevisions.merge(current.invalidatedProjectRevisions, uniquingKeysWith: max)
        for index in restored.messages.indices { restored.messages[index].continuation = nil }
        restored.recoverInterruptedMessages()
        restored.updatedAt = Date()
        let removed = Set(current.messages.map(\.id)).subtracting(restored.messages.map(\.id))
        try database.transaction {
            try insertConversationRevision(displaced)
            try Self.persist(restored, in: database)
            try supersedeWork(in: current.id, except: UUID())
            try reconcileAutomaticMemoryAfterEdit(conversationID: current.id, removedMessageIDs: removed)
        }
        return restored
    }
}
