import Foundation

public struct MemoryChange: Codable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var memoryID: UUID
    public var createdAt: Date = Date()
    public var action: String
    public var actor: String
    public var before: SavedMemory?
    public var after: SavedMemory
    public var operationID: String
    public var fingerprint: String
}

extension LocalStore {
    public func memory(_ id: UUID) throws -> SavedMemory? {
        guard let data = try database.execute("SELECT payload FROM memories WHERE id=?", [.text(id.uuidString)]).first?[0].data else { return nil }
        return try Self.decode(SavedMemory.self, data)
    }
    public func memoryChanges(offset: Int = 0, limit: Int = 25) throws -> [MemoryChange] {
        guard (0...100_000).contains(offset) else { throw AssistantError.invalidTool("Invalid history offset.") }
        return try database.execute("SELECT payload FROM memory_changes ORDER BY created_at DESC, rowid DESC LIMIT ? OFFSET ?", [.integer(Int64(min(max(limit, 1), 50))), .integer(Int64(offset))])
            .map { try Self.decode(MemoryChange.self, $0[0].data!) }
    }
    func memoryOperation(_ operationID: String, fingerprint: String) throws -> MemoryChange? {
        guard let payload = try database.execute("SELECT payload FROM memory_changes WHERE operation_id=?", [.text(operationID)]).first?[0].data else { return nil }
        let change = try Self.decode(MemoryChange.self, payload)
        guard change.fingerprint == fingerprint else { throw AssistantError.invalidTool("A repeated memory operation changed its arguments.") }
        return change
    }
    @discardableResult
    func recordMemory(_ proposal: SavedMemory, action: String, actor: String, operationID: String = UUID().uuidString, fingerprint: String = "", inExistingTransaction: Bool = false) throws -> MemoryChange {
        guard !proposal.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, proposal.title.utf8.count <= 200,
              !proposal.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, proposal.text.utf8.count <= 16_384,
              proposal.source.utf8.count <= 600, (proposal.sourceQuote?.utf8.count ?? 0) <= 1200 else { throw AssistantError.invalidTool("Use a focused memory with a short title and source.") }
        if let old = try memoryOperation(operationID, fingerprint: fingerprint) { return old }
        let before = try memory(proposal.id)
        var after = proposal; after.revision = (before?.revision ?? 0) + 1; after.updatedAt = Date()
        let change = MemoryChange(memoryID: proposal.id, action: action, actor: actor, before: before, after: after, operationID: operationID, fingerprint: fingerprint)
        let write: () throws -> Void = {
            try self.database.execute("INSERT INTO memories(id,updated_at,payload) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET updated_at=excluded.updated_at,payload=excluded.payload", [.text(after.id.uuidString), .real(after.updatedAt.timeIntervalSince1970), .blob(try Self.encode(after))])
            try self.database.execute("INSERT INTO memory_changes(id,memory_id,created_at,operation_id,payload) VALUES(?,?,?,?,?)", [.text(change.id.uuidString), .text(after.id.uuidString), .real(change.createdAt.timeIntervalSince1970), .text(operationID), .blob(try Self.encode(change))])
        }
        if inExistingTransaction { try write() } else { try database.transaction(write) }
        return change
    }
    public func undoMemoryChange(_ id: UUID) throws -> SavedMemory {
        guard let payload = try database.execute("SELECT payload FROM memory_changes WHERE id=?", [.text(id.uuidString)]).first?[0].data else { throw AssistantError.invalidTool("This change is no longer available.") }
        let change = try Self.decode(MemoryChange.self, payload)
        guard let current = try memory(change.memoryID), current.revision == change.after.revision else { throw AssistantError.invalidTool("This memory changed again. Review its latest version before undoing an older change.") }
        var restored = change.before ?? current
        if change.before == nil { restored.status = .forgotten }
        restored.basis = .userEdited
        restored.source = "Restored by the user from memory history"
        return try recordMemory(restored, action: "undone", actor: "user").after
    }
    public func applyAutomaticMemory(_ call: ToolCall, conversationID: UUID, remote: Bool, localOnly: Bool, health: Bool, workspaceEnabled: Bool = false) throws -> MemoryChange {
        try Task.checkCancellation()
        let args = call.arguments, fingerprint = try args.jsonString(), operationID = conversationID.uuidString + ":" + call.id
        guard let sourceID = UUID(uuidString: args["source_message_id"]?.stringValue ?? ""), let quote = args["evidence"]?.stringValue,
              !quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, quote.utf8.count <= 1200 else { throw AssistantError.invalidTool("Reference a user message and a short exact supporting quote.") }
        let sourceChatText = args["source_conversation_id"]?.stringValue ?? ""
        guard sourceChatText.isEmpty || UUID(uuidString: sourceChatText) != nil else { throw AssistantError.invalidTool("Use a valid source conversation ID, or empty for this chat.") }
        let sourceChat = UUID(uuidString: sourceChatText) ?? conversationID
        guard sourceChat == conversationID || workspaceEnabled else { throw AssistantError.invalidTool("Cross-chat memory evidence requires workspace history access.") }
        let source = sourceChat == conversationID ? try message(sourceID, in: sourceChat) : try sharedHistoryMessage(sourceID, conversationID: sourceChat, folderID: nil, remote: remote)
        guard source.role == .user, source.text.contains(quote), !remote || (!source.containsLocalOnlyContext && !source.containsHealthData) else { throw AssistantError.invalidTool("Memory evidence must be an eligible exact excerpt from a user message in this conversation, not a tool result or assistant inference.") }
        if let prior = try memoryOperation(operationID, fingerprint: fingerprint) {
            guard let current = try memory(prior.memoryID), !remote || current.allowsConnectedModels,
                  current.conversationID == nil || current.conversationID == conversationID else { throw AssistantError.invalidTool("This memory operation is outside the current access scope.") }
            return prior
        }
        let rawID = args["memory_id"]?.stringValue ?? ""
        let old: SavedMemory?
        if rawID.isEmpty { old = nil }
        else {
            guard let id = UUID(uuidString: rawID), let found = try memory(id), found.isCurrent(),
                  found.conversationID == nil || found.conversationID == conversationID,
                  !remote || found.allowsConnectedModels else { throw AssistantError.invalidTool("Read an eligible current memory before changing it.") }
            old = found
        }
        guard let expected = Int(args["expected_revision"]?.stringValue ?? ""), expected == (old?.revision ?? 0) else { throw AssistantError.invalidTool("This memory changed. Read its current revision before updating it.") }
        if let old {
            let evidenceDate = old.basis == .userEdited ? old.updatedAt : (old.sourceMessageCreatedAt ?? old.updatedAt)
            guard old.basis == .userEdited ? source.createdAt > evidenceDate : source.createdAt >= evidenceDate else { throw AssistantError.invalidTool("This memory has newer evidence or a later user edit. Do not overwrite it using an older conversation.") }
        }
        if call.name == "forget_memory" {
            guard var note = old else { throw AssistantError.invalidTool("Choose an existing memory to forget.") }
            note.status = .forgotten
            note.basis = .stated; note.sourceConversationID = sourceChat; note.sourceMessageID = sourceID; note.sourceQuote = quote; note.sourceMessageCreatedAt = source.createdAt
            return try recordMemory(note, action: "forgotten", actor: "assistant", operationID: operationID, fingerprint: fingerprint)
        }
        guard let title = args["title"]?.stringValue, let text = args["text"]?.stringValue,
              let kind = MemoryKind(rawValue: args["kind"]?.stringValue ?? ""),
              let basis = MemoryBasis(rawValue: args["basis"]?.stringValue ?? ""), basis != .userEdited,
              let scope = args["scope"]?.stringValue, ["global", "conversation"].contains(scope), text.utf8.count <= 4000 else { throw AssistantError.invalidTool("Use a short fact, a valid kind, stated/inferred basis, and global/conversation scope.") }
        let credentialPattern = #"(?i)(sk-[a-z0-9_-]{20,}|gh[pousr]_[a-z0-9]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|(?:password|passcode|recovery code|api key)\s*(?:is|:|=)\s*\S+)"#
        guard (text + " " + quote).range(of: credentialPattern, options: .regularExpression) == nil else { throw AssistantError.invalidTool("Credentials belong in secure account settings, not saved memory.") }
        if basis == .inferred, let old, old.basis != .inferred { throw AssistantError.invalidTool("Do not replace a stated or user-edited memory with an inference. Keep the inference separate and tentative.") }
        let forgotten = try database.execute("""
            SELECT 1 FROM memories m JOIN memory_changes h ON h.memory_id=m.id
            WHERE json_extract(CAST(m.payload AS TEXT),'$.status')='forgotten' AND (
              (json_extract(CAST(h.payload AS TEXT),'$.before.sourceMessageID')=? AND json_extract(CAST(h.payload AS TEXT),'$.before.sourceQuote')=?) OR
              (json_extract(CAST(h.payload AS TEXT),'$.after.sourceMessageID')=? AND json_extract(CAST(h.payload AS TEXT),'$.after.sourceQuote')=?)) LIMIT 1
            """, [.text(sourceID.uuidString), .text(quote), .text(sourceID.uuidString), .text(quote)])
        guard old != nil || forgotten.isEmpty else { throw AssistantError.invalidTool("That source was previously forgotten. Do not automatically recreate it; the user can restore it in memory history.") }
        var note = old ?? SavedMemory(title: title, text: text, allowsConnectedModels: remote && !localOnly && !health)
        let profileKey = args["profile_key"]?.stringValue ?? ""
        guard ["", "preferred_name", "occupation", "interests"].contains(profileKey), profileKey != "preferred_name" || (basis == .stated && text.count <= 60 && !text.contains("\n")) else { throw AssistantError.invalidTool("Use a supported profile field; a preferred name must be stated by the user and short.") }
        note.profileKey = profileKey.isEmpty ? nil : profileKey
        note.title = title; note.text = text; note.kind = kind; note.basis = basis
        note.status = basis == .inferred ? .tentative : .active; note.confirmedAt = nil
        note.conversationID = scope == "global" ? nil : conversationID
        if localOnly || health || source.containsLocalOnlyContext || source.containsHealthData { note.allowsConnectedModels = false }
        note.source = basis == .inferred ? "Assistant inference from a user message" : "User statement summarized by the assistant"
        note.sourceConversationID = sourceChat; note.sourceMessageID = sourceID; note.sourceQuote = quote; note.sourceMessageCreatedAt = source.createdAt
        let expiry = args["expires_at"]?.stringValue ?? ""
        if expiry.isEmpty { note.expiresAt = nil }
        else {
            guard let date = ISO8601DateFormatter().date(from: expiry), date > Date() else { throw AssistantError.invalidTool("Use a future ISO8601 expiry with time zone, or empty for no expiry.") }
            note.expiresAt = date
        }
        return try recordMemory(note, action: old == nil ? "remembered" : "updated", actor: "assistant", operationID: operationID, fingerprint: fingerprint)
    }
    /// Called inside the transcript edit transaction. User-managed notes are independent;
    /// automatic changes sourced solely from removed messages must not leak the old request.
    func reconcileAutomaticMemoryAfterEdit(conversationID: UUID, removedMessageIDs: Set<UUID>) throws {
        let candidates = try database.execute("SELECT payload FROM memories WHERE json_extract(CAST(payload AS TEXT),'$.sourceConversationID')=?", [.text(conversationID.uuidString)])
            .map { try Self.decode(SavedMemory.self, $0[0].data!) }
        for note in candidates where note.basis != .userEdited && note.sourceMessageID.map(removedMessageIDs.contains) == true {
            let changes = try database.execute("SELECT payload FROM memory_changes WHERE memory_id=? ORDER BY created_at DESC,rowid DESC LIMIT 1000", [.text(note.id.uuidString)])
                .map { try Self.decode(MemoryChange.self, $0[0].data!) }
            let prior = changes.compactMap(\.before).first { memory in
                memory.basis == .userEdited || memory.sourceConversationID != conversationID || memory.sourceMessageID.map { !removedMessageIDs.contains($0) } == true
            }
            var restored = prior ?? note
            if prior == nil { restored.status = .forgotten }
            try recordMemory(restored, action: "source_edited", actor: "app", inExistingTransaction: true)
        }
    }
}
