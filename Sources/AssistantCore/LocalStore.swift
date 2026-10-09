import Foundation

/// The app owns durable history independently of provider sessions. Credentials are never stored here.
public actor LocalStore {
    public nonisolated let root: URL
    private let files = FileManager.default
    private let database: SQLiteDatabase

    public init(root: URL) throws {
        self.root = root
        for directory in [root, root.appendingPathComponent("conversations"), root.appendingPathComponent("captures")] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let database = try SQLiteDatabase(url: root.appendingPathComponent("assistant.sqlite"))
        try Self.prepare(database, root: root)
        self.database = database
    }
    public func save(_ conversation: Conversation) throws {
        var updated = conversation
        updated.updatedAt = Date()
        try database.transaction { try Self.persist(updated, in: database) }
    }
    public func loadConversation(_ id: UUID) throws -> Conversation {
        guard let record = try database.execute("SELECT payload FROM conversations WHERE id = ?", [.text(id.uuidString)]).first?[0].data else {
            throw AssistantError.provider("The saved conversation could not be found.")
        }
        var c = try Self.decode(Conversation.self, record)
        c.messages = try database.execute("SELECT payload FROM messages WHERE conversation_id = ? ORDER BY ordinal", [.text(id.uuidString)])
            .map { row in try Self.decode(Message.self, row[0].data!) }
        c.recoverInterruptedMessages()
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
                                           messageCount: Int(row[1].number ?? 0))
            }
    }
    public func searchMessages(_ query: String, conversationID: UUID? = nil, limit: Int = 12) throws -> [HistoryMatch] {
        let terms = query.split(whereSeparator: \.isWhitespace).prefix(16).map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        guard !terms.isEmpty, query.utf8.count <= 1000 else { return [] }
        let scope = conversationID == nil ? "" : " AND m.conversation_id = ?"
        var parameters: [SQLValue] = [.text(terms.joined(separator: " AND "))]
        if let conversationID { parameters.append(.text(conversationID.uuidString)) }
        parameters.append(.integer(Int64(min(max(limit, 1), 30))))
        return try database.execute("""
            SELECT m.id, m.conversation_id, c.title, snippet(message_search, 0, '', '', ' … ', 36), m.payload
            FROM message_search JOIN messages m ON m.rowid = message_search.rowid
            JOIN conversations c ON c.id = m.conversation_id
            WHERE message_search MATCH ? \(scope) ORDER BY rank LIMIT ?
            """, parameters).map { row in
                let message = try Self.decode(Message.self, row[4].data!)
                return HistoryMatch(id: UUID(uuidString: row[0].text!)!, conversationID: UUID(uuidString: row[1].text!)!,
                                    title: row[2].text!, excerpt: row[3].text!, role: message.role, createdAt: message.createdAt)
            }
    }
    public func message(_ id: UUID, in conversationID: UUID) throws -> Message {
        guard let payload = try database.execute("SELECT payload FROM messages WHERE id = ? AND conversation_id = ?",
            [.text(id.uuidString), .text(conversationID.uuidString)]).first?[0].data else {
            throw AssistantError.invalidTool("That message is outside the current conversation or no longer exists.")
        }
        return try Self.decode(Message.self, payload)
    }

    public func saveArtifact(_ artifact: ArtifactRecord) throws {
        guard JavaScriptSandbox.validFilename(artifact.filename), artifact.content.utf8.count <= 2 * 1024 * 1024 else {
            throw AssistantError.invalidTool("Artifact name or content exceeds the supported limits.")
        }
        try database.execute("INSERT INTO artifacts(id, conversation_id, created_at, payload) VALUES(?,?,?,?)",
            [.text(artifact.id.uuidString), .text(artifact.conversationID.uuidString), .real(artifact.createdAt.timeIntervalSince1970), .blob(try Self.encode(artifact))])
    }
    public func artifacts(conversationID: UUID? = nil) throws -> [ArtifactRecord] {
        let scope = conversationID == nil ? "" : " WHERE conversation_id = ?"
        return try database.execute("SELECT payload FROM artifacts" + scope + " ORDER BY created_at DESC",
                                    conversationID.map { [.text($0.uuidString)] } ?? [])
            .map { try Self.decode(ArtifactRecord.self, $0[0].data!) }
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

    private static func prepare(_ database: SQLiteDatabase, root: URL) throws {
        let version = Int(try database.execute("PRAGMA user_version").first?[0].number ?? 0)
        guard version <= 1 else { throw AssistantError.unsupportedSchema(version) }
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
    private static func persist(_ conversation: Conversation, in database: SQLiteDatabase) throws {
        guard conversation.schemaVersion == 1 else { throw AssistantError.unsupportedSchema(conversation.schemaVersion) }
        guard Set(conversation.messages.map(\.id)).count == conversation.messages.count else {
            throw AssistantError.provider("The conversation contains duplicate message identities.")
        }
        var metadata = conversation; metadata.messages = []
        try database.execute("""
            INSERT INTO conversations(id,title,updated_at,payload) VALUES(?,?,?,?)
            ON CONFLICT(id) DO UPDATE SET title=excluded.title, updated_at=excluded.updated_at, payload=excluded.payload
            """, [.text(conversation.id.uuidString), .text(conversation.title), .real(conversation.updatedAt.timeIntervalSince1970), .blob(try encode(metadata))])
        for (position, message) in conversation.messages.enumerated() {
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
    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
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
