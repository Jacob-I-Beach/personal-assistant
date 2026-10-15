import Foundation

/// The app owns durable history independently of provider sessions. Credentials are never stored here.
public actor LocalStore {
    public nonisolated let root: URL
    public nonisolated let outputsRoot: URL?
    public nonisolated let initiallyContainsHealthData: Bool
    private let files = FileManager.default
    let database: SQLiteDatabase
    private var checkpointCache: (chat: Conversation, mutation: UInt64, external: Double)?

    public init(root: URL, outputsRoot: URL? = nil) throws {
        self.root = root
        self.outputsRoot = outputsRoot
        for directory in [root, root.appendingPathComponent("conversations"), root.appendingPathComponent("captures")] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let database = try SQLiteDatabase(url: root.appendingPathComponent("assistant.sqlite"))
        try Self.prepare(database, root: root)
        try Self.prepareRevisionStorage(database)
        // Earlier versions could leave live revision rows after their parent
        // was deleted. These are app-owned chat histories, not exported files.
        try database.transaction {
            for (history, parent) in [("artifact_history", "artifacts"), ("surface_history", "work_surfaces")] {
                let present = try database.execute("SELECT name FROM sqlite_master WHERE type='table' AND name IN (?,?)", [.text(history), .text(parent)])
                if present.count == 2 { try database.execute("DELETE FROM \(history) WHERE NOT EXISTS(SELECT 1 FROM \(parent) p WHERE p.id=\(history).id)") }
            }
        }
        self.database = database
        self.initiallyContainsHealthData = try Self.hasRetainedHealthData(database)
    }
    public func hasRetainedHealthData() throws -> Bool { try Self.hasRetainedHealthData(database) }
    private static func hasRetainedHealthData(_ database: SQLiteDatabase) throws -> Bool {
        let tables = Set(try database.execute("SELECT name FROM sqlite_master WHERE type='table'").compactMap { $0[0].text })
        for table in ["messages", "artifacts", "workspace_files", "artifact_history", "work_surfaces", "surface_history", "project_workspaces", "work_turns"] where tables.contains(table) {
            if try !database.execute("SELECT 1 FROM \(table) WHERE json_extract(CAST(payload AS TEXT),'$.containsHealthData')=1 LIMIT 1").isEmpty { return true }
        }
        if try !database.execute("SELECT 1 FROM conversation_revisions WHERE contains_health=1 LIMIT 1").isEmpty { return true }
        if tables.contains("tool_operations"), try !database.execute("SELECT 1 FROM tool_operations WHERE json_extract(CAST(payload AS TEXT),'$.health')=1 OR json_extract(CAST(payload AS TEXT),'$.result.containsHealthData')=1 LIMIT 1").isEmpty { return true }
        return false
    }

    public func save(_ conversation: Conversation) throws {
        var updated = conversation
        updated.updatedAt = Date()
        let external = try database.execute("PRAGMA data_version").first?[0].number ?? 0
        let previous = checkpointCache.flatMap { $0.chat.id == updated.id && $0.mutation == database.mutationVersion && $0.external == external ? $0.chat : nil }
        try database.transaction { try Self.persist(updated, in: database, previous: previous) }
        checkpointCache = (updated, database.mutationVersion, external)
    }
    /// Commit an explicit user edit. Search uses the same transaction as the active transcript.
    public func prepareMessageEdit(in original: Conversation, messageID: UUID) throws -> Conversation {
        let saved = try loadConversation(original.id)
        guard try Self.encode(saved.messages) == Self.encode(original.messages),
              let index = original.messages.firstIndex(where: { $0.id == messageID && $0.role == .user }) else {
            throw AssistantError.provider("This conversation changed. Open the message again before editing it.")
        }
        var revised = original
        let removed = original.messages[index...]
        let calls = Set(removed.flatMap(\.toolCalls).map(\.id))
        let retainedFiles = Set(original.messages[..<index].flatMap(\.fileIDs))
        let threshold = saved.messages[index].createdAt
        for artifact in try artifacts() where artifact.conversationID == original.id {
            if artifact.createdAt >= threshold || artifact.sourceCallID.map(calls.contains) == true
                || artifact.lastMutationCallID.map(calls.contains) == true || artifact.updatedAt.map({ $0 >= threshold }) == true
                || (artifact.revision > 1 && artifact.updatedAt == nil) {
                revised.excludedArtifactIDs.insert(artifact.id)
            }
        }
        for surface in try surfaces(conversationID: original.id) {
            if surface.updatedAt >= threshold || calls.contains(surface.sourceCallID) || surface.lastMutationCallID.map(calls.contains) == true {
                revised.excludedSurfaceIDs.insert(surface.id)
            }
        }
        var invalidatedProject: ProjectWorkspace?
        if var project = try projectWorkspaces().first(where: { $0.id == (original.folderID ?? original.id) }), project.lastMutationWasUserEdit != true,
           (project.lastMutationConversationID ?? project.sourceConversationID) == original.id,
           project.updatedAt >= threshold || project.lastMutationCallID.map(calls.contains) == true {
            revised.invalidatedProjectRevisions[project.id.uuidString] = project.revision
            project.needsContextRebuild = true; invalidatedProject = project
        }
        for file in try workspaceFiles() where file.conversationID == original.id && !retainedFiles.contains(file.id) {
            revised.excludedFileIDs.insert(file.id)
        }
        revised.messages = Array(original.messages[..<index])
        // A title produced from the removed request is also prior context, even through search.
        revised.modelTitleOverride = "Conversation"
        if revised.titleWasGenerated { revised.title = "New conversation"; revised.needsAutomaticTitle = true }
        revised.updatedAt = Date()
        try prepareConversationRevisions()
        let revision = try makeConversationRevision(original, reason: "Before editing a request")
        try database.transaction {
            try insertConversationRevision(revision)
            try Self.persist(revised, in: database)
            try retireWork(in: original.id, sourceMessageIDs: Set(removed.map(\.id)), reason: "The source request was edited or removed.")
            if let project = invalidatedProject {
                try database.execute("UPDATE project_workspaces SET payload=? WHERE id=?", [.blob(try Self.encode(project)), .text(project.id.uuidString)])
            }
            try reconcileAutomaticMemoryAfterEdit(conversationID: original.id, removedMessageIDs: Set(removed.map(\.id)))
        }
        return revised
    }
    public func loadConversation(_ id: UUID, preservingStreaming: Bool = false) throws -> Conversation {
        guard let record = try database.execute("SELECT payload FROM conversations WHERE id = ?", [.text(id.uuidString)]).first?[0].data else {
            throw AssistantError.provider("The saved conversation could not be found.")
        }
        var c = try Self.decode(Conversation.self, record)
        c.messages = try database.execute("SELECT payload FROM messages WHERE conversation_id = ? ORDER BY ordinal", [.text(id.uuidString)])
            .map { row in try Self.decode(Message.self, row[0].data!) }
        if !preservingStreaming {
            var remoteMessages = Set<UUID>()
            // Losing the phone's observer does not stop a computer-owned task.
            // Leave its saved projection pending until authoritative events arrive.
            if let start = c.messages.lastIndex(where: \.isRequest),
               let work = try workTurn(c.messages[start].id), work.backendID.hasPrefix("companion:"),
               let run = try companionRun(work.id), run.jobID != nil, run.canReconnect,
               work.phase == .running || work.phase == .interrupted {
                remoteMessages = Set(c.messages[start...].filter { $0.providerID == work.backendID }.map(\.id))
            }
            c.recoverInterruptedMessages(preserving: remoteMessages)
        }
        return c
    }
    public func conversations() throws -> [Conversation] {
        try conversationSummaries().map { try loadConversation($0.id) }
    }
    public func conversationSummaries() throws -> [ConversationSummary] {
        try database.execute("SELECT payload, (SELECT COUNT(*) FROM messages WHERE conversation_id = conversations.id) FROM conversations ORDER BY updated_at DESC")
            .map { row in
                let conversation = try Self.decode(Conversation.self, row[0].data!)
                return ConversationSummary(id: conversation.id, title: conversation.title, updatedAt: conversation.updatedAt,
                                           messageCount: Int(row[1].number ?? 0), folderID: conversation.folderID, archivedAt: conversation.archivedAt)
            }
    }
    public func searchMessages(_ query: String, conversationID: UUID? = nil, limit: Int = 12, excludingLocalOnly: Bool = false,
                               folderID: UUID? = nil, includeArchived: Bool = false, excludingProtectedConversations: Bool = false) throws -> [HistoryMatch] {
        let terms = query.split(whereSeparator: \.isWhitespace).prefix(16).map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        guard !terms.isEmpty, query.utf8.count <= 1000 else { return [] }
        let scope = (conversationID == nil ? "" : " AND m.conversation_id = ?")
            + (excludingLocalOnly ? " AND COALESCE(json_extract(CAST(m.payload AS TEXT),'$.containsLocalOnlyContext'),0) = 0" : "")
            + (folderID == nil ? "" : " AND json_extract(CAST(c.payload AS TEXT),'$.folderID') = ?")
            + (includeArchived || conversationID != nil ? "" : " AND json_extract(CAST(c.payload AS TEXT),'$.archivedAt') IS NULL")
            + (excludingProtectedConversations ? " AND COALESCE(json_extract(CAST(c.payload AS TEXT),'$.networkDisabled'),0) = 0 AND NOT EXISTS(SELECT 1 FROM messages p WHERE p.conversation_id=c.id AND (COALESCE(json_extract(CAST(p.payload AS TEXT),'$.containsLocalOnlyContext'),0)=1 OR COALESCE(json_extract(CAST(p.payload AS TEXT),'$.containsHealthData'),0)=1))" : "")
        var parameters: [SQLValue] = [.text(terms.joined(separator: " AND "))]
        if let conversationID { parameters.append(.text(conversationID.uuidString)) }
        if let folderID { parameters.append(.text(folderID.uuidString)) }
        parameters.append(.integer(Int64(min(max(limit, 1), 30))))
        let sql = """
            SELECT m.id, m.conversation_id, COALESCE(json_extract(CAST(c.payload AS TEXT),'$.modelTitleOverride'),c.title), snippet(message_search, 0, '', '', ' … ', 36), m.payload
            FROM message_search JOIN messages m ON m.rowid = message_search.rowid
            JOIN conversations c ON c.id = m.conversation_id
            WHERE message_search MATCH ? AND json_extract(CAST(m.payload AS TEXT),'$.role') IN ('user','assistant') \(scope) ORDER BY rank LIMIT ?
            """
        var rows = try database.execute(sql, parameters)
        var related = false
        if rows.isEmpty {
            let expanded = RetrievalTerms.terms(query).sorted().prefix(24).map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"*" }
            if !expanded.isEmpty {
                parameters[0] = .text(expanded.joined(separator: " OR "))
                rows = try database.execute(sql, parameters); related = !rows.isEmpty
            }
        }
        return try rows.map { row in
                let message = try Self.decode(Message.self, row[4].data!)
                return HistoryMatch(id: UUID(uuidString: row[0].text!)!, conversationID: UUID(uuidString: row[1].text!)!,
                                    title: row[2].text!, excerpt: row[3].text!, role: message.role, createdAt: message.createdAt, sourceFingerprint: HistoryLanding.fingerprint(message.text), relatedWords: related)
            }
    }
    public func message(_ id: UUID, in conversationID: UUID) throws -> Message {
        guard let payload = try database.execute("SELECT payload FROM messages WHERE id = ? AND conversation_id = ?",
            [.text(id.uuidString), .text(conversationID.uuidString)]).first?[0].data else {
            throw AssistantError.invalidTool("That message is outside the current conversation or no longer exists.")
        }
        return try Self.decode(Message.self, payload)
    }

    public func folders() throws -> [ChatFolder] {
        try database.execute("SELECT payload FROM folders ORDER BY name COLLATE NOCASE")
            .map { try Self.decode(ChatFolder.self, $0[0].data!) }
    }
    public func saveFolder(_ folder: ChatFolder) throws {
        var folder = folder; folder.name = folder.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !folder.name.isEmpty, folder.name.count <= 64, folder.instructions.utf8.count <= 4000 else {
            throw AssistantError.provider("Use a folder name up to 64 characters and focused instructions up to 4 KB.")
        }
        guard try !folders().contains(where: { $0.id != folder.id && $0.name.caseInsensitiveCompare(folder.name) == .orderedSame }) else {
            throw AssistantError.provider("A folder with that name already exists.")
        }
        try database.execute("INSERT INTO folders(id,name,payload) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name,payload=excluded.payload",
            [.text(folder.id.uuidString), .text(folder.name), .blob(try Self.encode(folder))])
    }
    public func renameConversation(_ id: UUID, title: String) throws {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 160 else { throw AssistantError.provider("Use a chat title between 1 and 160 characters.") }
        var conversation = try loadConversation(id); conversation.title = title; conversation.needsAutomaticTitle = false
        conversation.titleWasGenerated = false; conversation.modelTitleOverride = nil
        try save(conversation)
    }
    public func moveConversation(_ id: UUID, to folderID: UUID?) throws {
        if let folderID, try !folders().contains(where: { $0.id == folderID }) { throw AssistantError.provider("That folder no longer exists.") }
        var conversation = try loadConversation(id); conversation.folderID = folderID
        try save(conversation)
    }
    public func setArchived(_ id: UUID, archived: Bool) throws {
        var conversation = try loadConversation(id); conversation.archivedAt = archived ? Date() : nil
        try save(conversation)
    }
    public func removeFolder(_ id: UUID) throws {
        let affected = try conversations().filter { $0.folderID == id }
        try database.transaction {
            for var conversation in affected { conversation.folderID = nil; try Self.persist(conversation, in: database) }
            try database.execute("DELETE FROM folders WHERE id = ?", [.text(id.uuidString)])
        }
    }
    public func removeConversation(_ id: UUID) throws {
        let generated = try artifacts(conversationID: id)
        for file in try workspaceFiles() where file.conversationID == id { try removeWorkspaceFile(file.id) }
        // Exports are regenerable caches. Remove them before committing the data deletion.
        let exportRoot = root.appendingPathComponent("exports").resolvingSymlinksInPath().path + "/"
        for artifact in generated {
            let directory = root.appendingPathComponent("exports").appendingPathComponent(artifact.id.uuidString)
            guard directory.resolvingSymlinksInPath().path.hasPrefix(exportRoot) else { throw AssistantError.provider("An export is outside the app's cache directory.") }
            if files.fileExists(atPath: directory.path) { try files.removeItem(at: directory) }
        }
        try database.transaction {
            for artifact in generated { try database.execute("DELETE FROM metadata WHERE key IN (?,?)", [.text("artifact-draft:" + artifact.id.uuidString), .text("artifact-draft-state:" + artifact.id.uuidString)]) }
            for (history, parent) in [("artifact_history", "artifacts"), ("surface_history", "work_surfaces")] {
                let present = try database.execute("SELECT name FROM sqlite_master WHERE type='table' AND name IN (?,?)", [.text(history), .text(parent)])
                if present.count == 2 { try database.execute("DELETE FROM \(history) WHERE id IN (SELECT id FROM \(parent) WHERE conversation_id=?)", [.text(id.uuidString)]) }
            }
            // Optional tables may not exist in an older installation until their feature is used.
            for table in ["work_turns", "tool_operations", "prepared_routes", "task_questions"] {
                if !(try database.execute("SELECT name FROM sqlite_master WHERE type='table' AND name=?", [.text(table)])).isEmpty {
                    try database.execute("DELETE FROM \(table) WHERE conversation_id=?", [.text(id.uuidString)])
                }
            }
            if !(try database.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='assistant_inbox'")).isEmpty {
                try database.execute("DELETE FROM assistant_inbox WHERE json_extract(CAST(payload AS TEXT),'$.conversationID')=?", [.text(id.uuidString)])
            }
            try database.execute("DELETE FROM artifacts WHERE conversation_id = ?", [.text(id.uuidString)])
            try database.execute("DELETE FROM memories WHERE json_extract(CAST(payload AS TEXT),'$.conversationID') = ?", [.text(id.uuidString)])
            try database.execute("DELETE FROM conversations WHERE id = ?", [.text(id.uuidString)])
        }
    }
    public func sharedHistoryMessage(_ id: UUID, conversationID: UUID, folderID: UUID?, remote: Bool) throws -> Message {
        let conversation = try loadConversation(conversationID)
        guard conversation.archivedAt == nil, folderID == nil || conversation.folderID == folderID else {
            throw AssistantError.invalidTool("That chat is outside the current workspace search scope.")
        }
        if remote, conversation.networkDisabled || conversation.messages.contains(where: { $0.containsLocalOnlyContext || $0.containsHealthData }) {
            throw AssistantError.invalidTool("That chat contains protected context and is not available to connected-model workspace search.")
        }
        return try message(id, in: conversationID)
    }

    public func saveArtifact(_ artifact: ArtifactRecord) throws {
        guard JavaScriptSandbox.validFilename(artifact.filename), artifact.content.utf8.count <= 2 * 1024 * 1024 else {
            throw AssistantError.invalidTool("Artifact name or content exceeds the supported limits.")
        }
        try database.execute("INSERT INTO artifacts(id, conversation_id, created_at, payload) VALUES(?,?,?,?)",
            [.text(artifact.id.uuidString), .text(artifact.conversationID.uuidString), .real(artifact.createdAt.timeIntervalSince1970), .blob(try Self.encode(artifact))])
    }
    public func saveArtifactDraft(id: UUID, text: String?, baseRevision: Int? = nil) throws {
        try Task.checkCancellation()
        let oldKey = "artifact-draft:" + id.uuidString, key = "artifact-draft-state:" + id.uuidString
        guard let text else { try database.execute("DELETE FROM metadata WHERE key IN (?,?)", [.text(key), .text(oldKey)]); return }
        guard !(try database.execute("SELECT id FROM artifacts WHERE id=?", [.text(id.uuidString)])).isEmpty else { throw AssistantError.provider("The saved document is no longer available. Your editor text has been kept on screen.") }
        guard text.utf8.count <= 2 * 1024 * 1024 else { throw AssistantError.provider("This draft exceeds the supported editor size.") }
        let value = String(decoding: try JSONEncoder().encode(ArtifactDraft(text: text, baseRevision: baseRevision)), as: UTF8.self)
        try database.transaction {
            try database.execute("INSERT INTO metadata(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", [.text(key), .text(value)])
            try database.execute("DELETE FROM metadata WHERE key=?", [.text(oldKey)])
        }
    }
    public func artifactDraft(id: UUID) throws -> String? {
        try artifactDraftRecord(id: id)?.text
    }
    public func artifacts(conversationID: UUID? = nil) throws -> [ArtifactRecord] {
        let scope = conversationID == nil ? "" : " WHERE conversation_id = ?"
        return try database.execute("SELECT payload FROM artifacts" + scope + " ORDER BY created_at DESC",
                                    conversationID.map { [.text($0.uuidString)] } ?? [])
            .map { try Self.decode(ArtifactRecord.self, $0[0].data!) }
    }
    public func artifactRecord(_ id: UUID) throws -> ArtifactRecord {
        guard let payload = try database.execute("SELECT payload FROM artifacts WHERE id=?", [.text(id.uuidString)]).first?[0].data else { throw AssistantError.provider("This saved document is no longer available.") }
        return try Self.decode(ArtifactRecord.self, payload)
    }
    public func exportArtifact(_ artifact: ArtifactRecord) throws -> URL {
        guard JavaScriptSandbox.validFilename(artifact.filename),
              let saved = try artifacts(conversationID: artifact.conversationID).first(where: { $0.id == artifact.id }) else {
            throw AssistantError.invalidTool("The artifact could not be found.")
        }
        let directory = root.appendingPathComponent("exports").appendingPathComponent(saved.id.uuidString)
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(saved.filename)
        try Data(saved.content.utf8).write(to: url, options: .atomic)
        return url
    }
    public func enqueueWatchRequest(_ request: WatchRequest) throws -> Bool {
        guard request.isValid() else { throw AssistantError.invalidTool("This Watch request is empty, too large, or expired.") }
        let payload = try WatchWire.encode(request)
        return try database.transaction {
            if let existing = try database.execute("SELECT payload FROM watch_requests WHERE id = ?", [.text(request.id.uuidString)]).first?[0].data {
                guard existing == payload else { throw AssistantError.invalidTool("A repeated Watch request changed its contents.") }
                return false
            }
            try database.execute("INSERT INTO watch_requests(id,created_at,state,payload) VALUES(?,?,'queued',?)",
                [.text(request.id.uuidString), .real(request.createdAt.timeIntervalSince1970), .blob(payload)])
            return true
        }
    }
    public func queuedWatchRequests() throws -> [WatchRequest] {
        try database.execute("SELECT payload FROM watch_requests WHERE state = 'queued' ORDER BY created_at LIMIT 20")
            .map { try WatchWire.decode(WatchRequest.self, data: $0[0].data!) }
    }
    public func pendingWatchRequests() throws -> [WatchRequest] {
        try database.execute("SELECT payload FROM watch_requests WHERE state IN ('queued','needsPhone','working') ORDER BY created_at LIMIT 40")
            .map { try WatchWire.decode(WatchRequest.self, data: $0[0].data!) }
    }
    public func recoverWatchRequests() throws {
        for row in try database.execute("SELECT reply FROM watch_requests WHERE state = 'working'") {
            guard let data = row[0].data else { continue }
            var reply = try WatchWire.decode(WatchReply.self, data: data)
            reply.state = .needsPhone; reply.message = "The app was interrupted. Open Watch requests on iPhone to continue the saved task."
            try saveWatchReply(reply)
        }
    }
    public func memories() throws -> [SavedMemory] {
        try database.execute("SELECT payload FROM memories WHERE COALESCE(json_extract(CAST(payload AS TEXT),'$.status'),'active') != 'forgotten' ORDER BY updated_at DESC")
            .map { try Self.decode(SavedMemory.self, $0[0].data!) }
    }
    public func saveMemory(_ memory: SavedMemory) throws {
        guard !memory.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              memory.title.utf8.count <= 200, !memory.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              memory.text.utf8.count <= 16_384, memory.source.utf8.count <= 600 else { throw AssistantError.provider("Give this memory a title and a focused note, up to 16 KB, with a short source label.") }
        var updated = memory; updated.basis = .userEdited
        try recordMemory(updated, action: "saved", actor: "user")
    }
    public func removeMemory(_ id: UUID) throws {
        guard var note = try memory(id), note.status != .forgotten else { return }
        note.status = .forgotten; note.basis = .userEdited; try recordMemory(note, action: "forgotten", actor: "user")
    }
    public func saveWatchReply(_ reply: WatchReply) throws {
        try database.execute("UPDATE watch_requests SET state = ?, reply = ? WHERE id = ?",
            [.text(reply.state.rawValue), .blob(try WatchWire.encode(reply)), .text(reply.requestID.uuidString)])
    }
    public func watchReply(_ id: UUID) throws -> WatchReply? {
        guard let data = try database.execute("SELECT reply FROM watch_requests WHERE id = ?", [.text(id.uuidString)]).first?[0].data else { return nil }
        return try WatchWire.decode(WatchReply.self, data: data)
    }

    private static func prepare(_ database: SQLiteDatabase, root: URL) throws {
        let version = Int(try database.execute("PRAGMA user_version").first?[0].number ?? 0)
        guard version <= 6 else { throw AssistantError.unsupportedSchema(version) }
        if version == 0 {
            try database.transaction {
                try database.execute("CREATE TABLE conversations(id TEXT PRIMARY KEY, title TEXT NOT NULL, updated_at REAL NOT NULL, payload BLOB NOT NULL)")
                try database.execute("CREATE TABLE messages(id TEXT PRIMARY KEY, conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE, ordinal INTEGER NOT NULL, text TEXT NOT NULL, payload BLOB NOT NULL)")
                try database.execute("CREATE INDEX message_order ON messages(conversation_id, ordinal)")
                try database.execute("CREATE VIRTUAL TABLE message_search USING fts5(text, content='messages', content_rowid='rowid')")
                try database.execute("CREATE TRIGGER message_insert AFTER INSERT ON messages BEGIN INSERT INTO message_search(rowid,text) VALUES(new.rowid,new.text); END")
                try database.execute("CREATE TRIGGER message_delete AFTER DELETE ON messages BEGIN INSERT INTO message_search(message_search,rowid,text) VALUES('delete',old.rowid,old.text); END")
                try database.execute("CREATE TRIGGER message_update AFTER UPDATE OF text ON messages WHEN old.text != new.text BEGIN INSERT INTO message_search(message_search,rowid,text) VALUES('delete',old.rowid,old.text); INSERT INTO message_search(rowid,text) VALUES(new.rowid,new.text); END")
                try database.execute("CREATE TABLE artifacts(id TEXT PRIMARY KEY, conversation_id TEXT NOT NULL, created_at REAL NOT NULL, payload BLOB NOT NULL)")
                try database.execute("CREATE TABLE metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL)")
                try database.execute("PRAGMA user_version = 1")
            }
        }
        if version < 2 {
            try database.transaction {
                try database.execute("CREATE TABLE watch_requests(id TEXT PRIMARY KEY, created_at REAL NOT NULL, state TEXT NOT NULL, payload BLOB NOT NULL, reply BLOB)")
                try database.execute("PRAGMA user_version = 2")
            }
        }
        if version < 3 {
            try database.transaction {
                try database.execute("CREATE TABLE memories(id TEXT PRIMARY KEY, updated_at REAL NOT NULL, payload BLOB NOT NULL)")
                try database.execute("PRAGMA user_version = 3")
            }
        }
        if version < 4 {
            try database.transaction {
                try database.execute("CREATE TABLE folders(id TEXT PRIMARY KEY, name TEXT NOT NULL, payload BLOB NOT NULL)")
                try database.execute("PRAGMA user_version = 4")
            }
        }
        if version < 5 {
            try database.transaction {
                try database.execute("CREATE TABLE workspace_files(id TEXT PRIMARY KEY, created_at REAL NOT NULL, payload BLOB NOT NULL)")
                try database.execute("PRAGMA user_version = 5")
            }
        }
        if version < 6 {
            try database.transaction {
                try database.execute("CREATE TABLE memory_changes(id TEXT PRIMARY KEY, memory_id TEXT NOT NULL REFERENCES memories(id) ON DELETE CASCADE, created_at REAL NOT NULL, operation_id TEXT NOT NULL UNIQUE, payload BLOB NOT NULL)")
                try database.execute("CREATE INDEX memory_change_order ON memory_changes(memory_id, created_at)")
                try database.execute("PRAGMA user_version = 6")
            }
        }
        if try database.execute("SELECT value FROM metadata WHERE key = 'legacy-import'").isEmpty {
            let legacy = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("conversations"), includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
            try database.transaction {
                for url in legacy {
                    let data = try Data(contentsOf: url)
                    guard data.count <= 40 * 1024 * 1024 else { throw AssistantError.provider("A legacy conversation is too large to import automatically. Its original file has been preserved.") }
                    let conversation = try decode(Conversation.self, data)
                    guard url.deletingPathExtension().lastPathComponent == conversation.id.uuidString else {
                        throw AssistantError.provider("A legacy conversation has mismatched identity. Its original file has been preserved.")
                    }
                    try persist(conversation, in: database)
                }
                try database.execute("INSERT INTO metadata(key,value) VALUES('legacy-import','complete')")
            }
        }
    }
    static func persist(_ conversation: Conversation, in database: SQLiteDatabase, previous: Conversation? = nil) throws {
        guard conversation.schemaVersion == 1 else { throw AssistantError.unsupportedSchema(conversation.schemaVersion) }
        if let folder = conversation.folderID, try database.execute("SELECT 1 FROM folders WHERE id = ?", [.text(folder.uuidString)]).isEmpty {
            throw AssistantError.provider("The selected folder no longer exists. Choose another folder before saving.")
        }
        guard Set(conversation.messages.map(\.id)).count == conversation.messages.count else {
            throw AssistantError.provider("The conversation contains duplicate message identities.")
        }
        var metadata = conversation; metadata.messages = []
        try database.execute("""
            INSERT INTO conversations(id,title,updated_at,payload) VALUES(?,?,?,?)
            ON CONFLICT(id) DO UPDATE SET title=excluded.title, updated_at=excluded.updated_at, payload=excluded.payload
            """, [.text(conversation.id.uuidString), .text(conversation.title), .real(conversation.updatedAt.timeIntervalSince1970), .blob(try encode(metadata))])
        for (position, message) in conversation.messages.enumerated() {
            if let previous, position < previous.messages.count, previous.messages[position] == message { continue }
            let identity = try database.execute("SELECT conversation_id FROM messages WHERE id = ?", [.text(message.id.uuidString)]).first?[0].text
            guard identity == nil || identity == conversation.id.uuidString else {
                throw AssistantError.provider("A message belongs to another conversation.")
            }
            try database.execute("""
                INSERT INTO messages(id,conversation_id,ordinal,text,payload) VALUES(?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET ordinal=excluded.ordinal, text=excluded.text, payload=excluded.payload
                WHERE messages.ordinal != excluded.ordinal OR messages.payload != excluded.payload
                """, [.text(message.id.uuidString), .text(conversation.id.uuidString), .integer(Int64(position)), .text(message.text), .blob(try encode(message))])
        }
        // Normal generation appends or updates messages. Explicit truncation must also remove stale search entries.
        let ids = Set(conversation.messages.map { $0.id.uuidString })
        for row in try database.execute("SELECT id FROM messages WHERE conversation_id = ?", [.text(conversation.id.uuidString)]) {
            if let id = row[0].text, !ids.contains(id) { try database.execute("DELETE FROM messages WHERE id = ?", [.text(id)]) }
        }
    }
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
    static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
    public func saveCapture(_ observation: CaptureObservation, jpeg: Data) throws {
        try observation.validate()
        guard !jpeg.isEmpty, jpeg.count <= 30 * 1024 * 1024 else {
            throw AssistantError.invalidCapture("The capture image is empty or exceeds the capture size limit.")
        }
        let directory = captureDirectory(observation.id)
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        try jpeg.write(to: directory.appendingPathComponent("image.jpg"), options: .atomic)
        // The manifest is the commit record: no manifest is visible until the image write succeeded.
        try write(observation, to: directory.appendingPathComponent("observation.json"))
    }
    public func loadCapture(_ id: UUID) throws -> CaptureObservation {
        let observation: CaptureObservation = try read(captureDirectory(id).appendingPathComponent("observation.json"))
        guard observation.id == id else { throw AssistantError.invalidCapture("Capture identity mismatch.") }
        try observation.validate()
        return observation
    }
    public func captures() throws -> [CaptureObservation] {
        try files.contentsOfDirectory(at: root.appendingPathComponent("captures"), includingPropertiesForKeys: nil)
            .compactMap { UUID(uuidString: $0.lastPathComponent) }
            .filter { files.fileExists(atPath: captureDirectory($0).appendingPathComponent("observation.json").path) }
            .map { try loadCapture($0) }.sorted { $0.capturedAt > $1.capturedAt }
    }
    public func imageData(_ id: UUID) throws -> Data {
        _ = try loadCapture(id)
        return try Data(contentsOf: captureDirectory(id).appendingPathComponent("image.jpg"))
    }
    public func captureManifestURL(_ id: UUID) throws -> URL {
        _ = try loadCapture(id)
        return captureDirectory(id).appendingPathComponent("observation.json")
    }
    public func captureImageURL(_ id: UUID) throws -> URL {
        _ = try loadCapture(id)
        return captureDirectory(id).appendingPathComponent("image.jpg")
    }
    private func captureDirectory(_ id: UUID) -> URL { root.appendingPathComponent("captures").appendingPathComponent(id.uuidString) }
    private func conversationURL(_ id: UUID) -> URL { root.appendingPathComponent("conversations").appendingPathComponent(id.uuidString + ".json") }
    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: url, options: .atomic)
    }
    private func read<T: Decodable>(_ url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        guard data.count <= 40 * 1024 * 1024 else { throw AssistantError.invalidCapture("Saved record is unexpectedly large.") }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }
}
