import Foundation

/// Imported originals and locally generated binary documents. Text is a bounded extraction, never a substitute for the original.
public struct WorkspaceFile: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var filename: String
    public var mediaType: String
    public var byteCount: Int
    public var text: String
    public var extractionNote: String
    public var createdAt: Date
    public var allowsWorkspaceSearch: Bool
    public var allowsConnectedModels: Bool
    public var conversationID: UUID?
    public var containsHealthData: Bool
    public init(id: UUID = UUID(), filename: String, mediaType: String, byteCount: Int, text: String,
                extractionNote: String = "", allowsWorkspaceSearch: Bool = false, allowsConnectedModels: Bool = false,
                conversationID: UUID? = nil, containsHealthData: Bool = false) {
        self.id = id; self.filename = filename; self.mediaType = mediaType; self.byteCount = byteCount
        self.text = text; self.extractionNote = extractionNote; self.createdAt = Date()
        self.allowsWorkspaceSearch = allowsWorkspaceSearch; self.allowsConnectedModels = allowsConnectedModels
        self.conversationID = conversationID; self.containsHealthData = containsHealthData
    }
    public var icon: String {
        switch URL(fileURLWithPath: filename).pathExtension.lowercased() {
        case "pdf": "doc.richtext"
        case "csv", "tsv", "xlsx": "tablecells"
        case "pptx": "rectangle.on.rectangle"
        case "js", "py", "swift", "json", "html": "curlybraces"
        default: "doc.text"
        }
    }
    public static func validateFilename(_ name: String) throws {
        guard !name.isEmpty, name.utf8.count <= 240, name != ".", name != "..",
              !name.contains(where: { "/\\:\0".contains($0) || $0.isNewline || $0.asciiValue.map { $0 < 32 } == true }),
              !name.hasPrefix("."), !name.hasSuffix("."), !name.hasSuffix(" ") else {
            throw AssistantError.invalidTool("Use a simple filename without directories or control characters.")
        }
    }
}

extension LocalStore {
    public func workspaceFiles() throws -> [WorkspaceFile] {
        try database.execute("SELECT payload FROM workspace_files ORDER BY created_at DESC")
            .map { try Self.decode(WorkspaceFile.self, $0[0].data!) }
    }
    public func workspaceFile(_ id: UUID) throws -> WorkspaceFile {
        guard let data = try database.execute("SELECT payload FROM workspace_files WHERE id = ?", [.text(id.uuidString)]).first?[0].data else {
            throw AssistantError.invalidTool("That file is no longer in the app's Library.")
        }
        return try Self.decode(WorkspaceFile.self, data)
    }
    public func saveWorkspaceFile(_ file: WorkspaceFile, data: Data) throws {
        try WorkspaceFile.validateFilename(file.filename)
        guard file.byteCount == data.count, !data.isEmpty, data.count <= 25 * 1024 * 1024,
              file.text.utf8.count <= 2 * 1024 * 1024, file.extractionNote.utf8.count < 4000 else {
            throw AssistantError.invalidTool("Files must be nonempty and at most 25 MB; searchable text is limited to 2 MB.")
        }
        guard try database.execute("SELECT 1 FROM workspace_files WHERE id = ?", [.text(file.id.uuidString)]).isEmpty else {
            throw AssistantError.invalidTool("A file with that identity already exists; originals cannot be overwritten.")
        }
        let directory = root.appendingPathComponent("files").appendingPathComponent(file.id.uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(file.filename), options: .atomic)
        try database.execute("INSERT INTO workspace_files(id,created_at,payload) VALUES(?,?,?)",
            [.text(file.id.uuidString), .real(file.createdAt.timeIntervalSince1970), .blob(try Self.encode(file))])
    }
    public func workspaceFileURL(_ id: UUID) throws -> URL {
        let file = try workspaceFile(id)
        try WorkspaceFile.validateFilename(file.filename)
        let directory = root.appendingPathComponent("files").appendingPathComponent(id.uuidString)
        let url = directory.appendingPathComponent(file.filename)
        guard url.resolvingSymlinksInPath().deletingLastPathComponent() == directory.resolvingSymlinksInPath(),
              FileManager.default.fileExists(atPath: url.path) else { throw AssistantError.invalidTool("The original file is unavailable.") }
        return url
    }
    public func setFileSharing(_ id: UUID, workspace: Bool, connected: Bool) throws {
        var file = try workspaceFile(id)
        guard !file.containsHealthData || (!workspace && !connected) else {
            throw AssistantError.invalidTool("Health-derived files stay scoped to their original conversation.")
        }
        file.allowsWorkspaceSearch = workspace; file.allowsConnectedModels = connected
        try database.execute("UPDATE workspace_files SET payload = ? WHERE id = ?", [.blob(try Self.encode(file)), .text(id.uuidString)])
    }
    public func removeWorkspaceFile(_ id: UUID) throws {
        let url = try workspaceFileURL(id)
        // Both components are app-owned UUID/validated filename; never accept a path from the model.
        try FileManager.default.removeItem(at: url)
        try database.execute("DELETE FROM workspace_files WHERE id = ?", [.text(id.uuidString)])
    }
    func protectGeneratedFile(_ id: UUID, conversationID: UUID, health: Bool) throws {
        var file = try workspaceFile(id)
        guard file.conversationID == conversationID else { throw AssistantError.invalidTool("A generated file has mismatched ownership.") }
        file.containsHealthData = file.containsHealthData || health
        if file.containsHealthData { file.allowsWorkspaceSearch = false; file.allowsConnectedModels = false }
        try database.execute("UPDATE workspace_files SET payload = ? WHERE id = ?", [.blob(try Self.encode(file)), .text(id.uuidString)])
    }
    public func readableFiles(attached: Set<UUID>, workspace: Bool, remote: Bool, conversationID: UUID) throws -> [WorkspaceFile] {
        let excluded = Set(try conversations().flatMap(\.excludedFileIDs))
        return try workspaceFiles().filter { file in
            if excluded.contains(file.id) && !attached.contains(file.id) { return false }
            if file.containsHealthData { return file.conversationID == conversationID && attached.contains(file.id) }
            return attached.contains(file.id) || (workspace && file.allowsWorkspaceSearch && (!remote || file.allowsConnectedModels))
        }
    }
    public func readableArtifacts(conversationID: UUID, workspace: Bool, remote: Bool) throws -> [ArtifactRecord] {
        let chats = try conversations()
        let excluded = Set(chats.flatMap(\.excludedArtifactIDs))
        let permitted = Set(chats.filter { chat in
            chat.id == conversationID || (workspace && chat.archivedAt == nil && (!remote || (!chat.networkDisabled && !chat.containsHealthData && !chat.messages.contains(where: \.containsLocalOnlyContext))))
        }.map(\.id))
        return try artifacts().filter { !excluded.contains($0.id) && permitted.contains($0.conversationID) && (!remote || (!$0.containsLocalOnlyContext && (!$0.containsHealthData || $0.conversationID == conversationID))) }
    }
}
