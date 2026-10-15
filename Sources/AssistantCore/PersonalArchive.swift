import Foundation

public struct PersonalArchiveManifest: Codable, Sendable {
    public var version = 1
    public var createdAt = Date()
    public var id = UUID()
    public var includesPrivateData: Bool
    public var includesHealthData: Bool
    public var conversations: [Conversation]
    public var folders: [ChatFolder]
    public var artifacts: [ArtifactRecord]
    public var artifactHistory: [ArtifactRecord]
    public var files: [WorkspaceFile]
    public var captures: [CaptureObservation]
    public var memories: [SavedMemory]
    public var memoryHistory: [MemoryChange]
    public var inbox: [InboxEntry]
    public var projects: [ProjectWorkspace]
    public var surfaces: [WorkSurface]
    public var surfaceHistory: [WorkSurface]
    public var revisions: [ConversationRevision]
    public var drafts: [String: String]
    public var artifactDrafts: [String: String]
    public var exclusions: [String]
    public var binaries: [ArchiveBinary]
}
public struct ArchiveBinary: Codable, Sendable {
    public var id: UUID
    public var kind: String
    public var bytes: Int
    public var checksum: String
}
public struct ArchiveInspection: Sendable {
    public let manifest: PersonalArchiveManifest
    public let totalBytes: UInt64
}

/// An explicit local export, not a sync service. It contains typed app records
/// and length-delimited originals, never SQLite code, credentials or jobs.
public enum PersonalArchive {
    private static let magic = Data("PA-ARCHIVE-0001\n".utf8)
    private static let manifestLimit = 64 * 1024 * 1024
    private static let totalLimit: UInt64 = 8 * 1024 * 1024 * 1024
    static func checksum(_ data: Data) -> String {
        // Corruption detection only; this is not a signature or authorization.
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        return String(hash, radix: 16)
    }
    private static func readExactly(_ handle: FileHandle, _ count: Int) throws -> Data {
        var result = Data()
        while result.count < count {
            guard let chunk = try handle.read(upToCount: count - result.count), !chunk.isEmpty else { throw AssistantError.invalidTool("The archive is incomplete. Your current library was not changed.") }
            result.append(chunk)
        }
        return result
    }
    static func write(manifest: PersonalArchiveManifest, to url: URL, binary: (ArchiveBinary) throws -> Data) throws {
        let header = try LocalStore.encode(manifest)
        guard header.count <= manifestLimit, !FileManager.default.fileExists(atPath: url.path) else { throw AssistantError.invalidTool("Choose a new archive name. Existing files are never overwritten.") }
        _ = FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        var complete = false
        defer { try? handle.close(); if !complete { try? FileManager.default.removeItem(at: url) } }
        try handle.write(contentsOf: magic)
        var size = UInt64(header.count).littleEndian
        try withUnsafeBytes(of: &size) { try handle.write(contentsOf: Data($0)) }
        try handle.write(contentsOf: header)
        var total = UInt64(header.count)
        for entry in manifest.binaries {
            try Task.checkCancellation()
            let bytes = try binary(entry)
            total += UInt64(bytes.count)
            guard total <= totalLimit, bytes.count == entry.bytes, checksum(bytes) == entry.checksum else { throw AssistantError.invalidTool("A source file changed during export. Create the archive again.") }
            try handle.write(contentsOf: bytes)
        }
        try handle.synchronize(); complete = true
    }
    private static func read(_ url: URL, consume: ((ArchiveBinary, Data) throws -> Void)? = nil) throws -> ArchiveInspection {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        guard try readExactly(handle, magic.count) == magic else { throw AssistantError.invalidTool("This is not a supported Personal Assistant archive.") }
        let sizeData = try readExactly(handle, 8)
        let length = sizeData.enumerated().reduce(UInt64(0)) { $0 | (UInt64($1.element) << ($1.offset * 8)) }
        guard length > 0, length <= UInt64(manifestLimit) else { throw AssistantError.invalidTool("The archive manifest exceeds its supported limit.") }
        let manifest = try LocalStore.decode(PersonalArchiveManifest.self, readExactly(handle, Int(length)))
        try validate(manifest)
        var total = length + UInt64(magic.count + 8)
        for entry in manifest.binaries {
            try Task.checkCancellation()
            total += UInt64(entry.bytes)
            guard total <= totalLimit else { throw AssistantError.invalidTool("The archive exceeds 8 GB.") }
            let bytes = try readExactly(handle, entry.bytes)
            guard checksum(bytes) == entry.checksum else { throw AssistantError.invalidTool("An archive file failed its integrity check. Your current library was not changed.") }
            try consume?(entry, bytes)
        }
        guard (try handle.read(upToCount: 1))?.isEmpty != false else { throw AssistantError.invalidTool("Unexpected data follows the archive. Export it again from the source app.") }
        return ArchiveInspection(manifest: manifest, totalBytes: total)
    }
    public static func inspect(_ url: URL) throws -> ArchiveInspection { try read(url) }
    public static func stageRestore(_ url: URL, in parent: URL) async throws -> URL {
        let checked = try inspect(url)
        // A fresh UUID directory makes restore isolated and repeatable. No merge,
        // duplicate overwrite, credential import or automatic task resumption.
        let target = parent.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        #if os(iOS) || os(macOS)
        var protected = target; var resources = URLResourceValues(); resources.isExcludedFromBackup = true; try protected.setResourceValues(resources)
        #endif
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: target.path)
        #endif
        let store = try LocalStore(root: target)
        try await store.restoreArchiveRecords(checked.manifest)
        let second = try read(url) { entry, bytes in
            let filename: String
            let directory: URL
            if entry.kind == "capture" { directory = target.appendingPathComponent("captures").appendingPathComponent(entry.id.uuidString); filename = "image.jpg" }
            else {
                guard let file = checked.manifest.files.first(where: { $0.id == entry.id }) else { throw AssistantError.invalidTool("The archive's file identity changed.") }
                filename = file.filename; directory = target.appendingPathComponent("files").appendingPathComponent(entry.id.uuidString)
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try bytes.write(to: directory.appendingPathComponent(filename), options: .atomic)
        }
        guard second.manifest.id == checked.manifest.id,
              try LocalStore.encode(second.manifest) == LocalStore.encode(checked.manifest) else { throw AssistantError.invalidTool("The archive changed while restoring. It was not activated.") }
        try await store.verifyRestoredArchive(checked.manifest)
        try Data(checked.manifest.id.uuidString.utf8).write(to: target.appendingPathComponent("restore-verified"), options: .atomic)
        return target
    }
    private static func validate(_ value: PersonalArchiveManifest) throws {
        func unique<T: Hashable>(_ ids: [T]) -> Bool { Set(ids).count == ids.count }
        let chats = Set(value.conversations.map(\.id)), artifacts = Set(value.artifacts.map(\.id)), files = Set(value.files.map(\.id)), captures = Set(value.captures.map(\.id))
        guard value.version == 1, value.conversations.count <= 50_000, value.files.count <= 100_000,
              unique(value.conversations.map(\.id)), unique(value.conversations.flatMap(\.messages).map(\.id)), unique(value.artifacts.map(\.id)), unique(value.files.map(\.id)), unique(value.captures.map(\.id)), unique(value.folders.map(\.id)), unique(value.memories.map(\.id)), unique(value.inbox.map(\.id)), unique(value.projects.map(\.id)), unique(value.surfaces.map(\.id)), unique(value.revisions.map(\.id)),
              unique(value.binaries.map { $0.kind + $0.id.uuidString }) else { throw AssistantError.invalidTool("This archive has an unsupported version or duplicate identities.") }
        for item in value.binaries {
            guard item.bytes > 0, item.bytes <= 30 * 1024 * 1024,
                  item.kind == "file" ? files.contains(item.id) : item.kind == "capture" && captures.contains(item.id) else { throw AssistantError.invalidTool("Invalid archive file reference.") }
        }
        guard Set(value.binaries.filter { $0.kind == "file" }.map(\.id)) == files,
              Set(value.binaries.filter { $0.kind == "capture" }.map(\.id)) == captures else { throw AssistantError.invalidTool("The archive is missing original files.") }
        for file in value.files { try WorkspaceFile.validateFilename(file.filename); guard file.text.utf8.count <= 2 * 1024 * 1024, value.binaries.contains(where: { $0.kind == "file" && $0.id == file.id && $0.bytes == file.byteCount }) else { throw AssistantError.invalidTool("Invalid file metadata.") } }
        for item in value.artifacts + value.artifactHistory { try WorkspaceFile.validateFilename(item.filename); guard chats.contains(item.conversationID), item.content.utf8.count <= 2 * 1024 * 1024, item.revision >= 1 else { throw AssistantError.invalidTool("Invalid document owner or revision.") } }
        guard value.artifactHistory.allSatisfy({ artifacts.contains($0.id) }), value.revisions.allSatisfy({ chats.contains($0.conversation.id) }), value.projects.allSatisfy({ chats.contains($0.sourceConversationID) }), value.surfaces.allSatisfy({ chats.contains($0.conversationID) }) else { throw AssistantError.invalidTool("An archive record has no owning conversation.") }
        for capture in value.captures { try capture.validate() }
        for surface in value.surfaces + value.surfaceHistory { try WorkSurface.validate(surface.spec) }
        let folderIDs = Set(value.folders.map(\.id))
        guard value.conversations.allSatisfy({ $0.schemaVersion == 1 && ($0.folderID == nil || folderIDs.contains($0.folderID!)) }) else { throw AssistantError.invalidTool("A conversation references a missing folder.") }
        // Draft keys are chat UUIDs, not arbitrary filesystem locations.
        guard value.drafts.allSatisfy({ UUID(uuidString: $0.key).map(chats.contains) == true && $0.value.utf8.count <= 2 * 1024 * 1024 }), value.artifactDrafts.allSatisfy({ UUID(uuidString: $0.key).map(artifacts.contains) == true && $0.value.utf8.count <= 3 * 1024 * 1024 }) else { throw AssistantError.invalidTool("Invalid saved draft identity.") }
    }
}

extension LocalStore {
    public func exportPersonalArchive(to url: URL, includePrivate: Bool = false, includeHealth: Bool = false) throws -> ArchiveInspection {
        let allChats = try conversations()
        let allArtifacts = try artifacts(), allFiles = try workspaceFiles(), allProjects = try projectWorkspaces()
        let protectedOwners = Set(allArtifacts.filter { (!includePrivate && $0.containsLocalOnlyContext) || (!includeHealth && $0.containsHealthData) }.map(\.conversationID))
            .union(allFiles.filter { (!includePrivate && !$0.allowsConnectedModels) || (!includeHealth && $0.containsHealthData) }.compactMap(\.conversationID))
            .union(allProjects.filter { (!includePrivate && $0.containsLocalOnlyContext) || (!includeHealth && $0.containsHealthData) }.map(\.sourceConversationID))
        let chats = allChats.filter { !protectedOwners.contains($0.id) && (includeHealth || !$0.containsHealthData) && (includePrivate || (!$0.networkDisabled && !$0.messages.contains(where: \.containsLocalOnlyContext))) }
        let chatIDs = Set(chats.map(\.id))
        let documents = allArtifacts.filter { chatIDs.contains($0.conversationID) && (includePrivate || !$0.containsLocalOnlyContext) && (includeHealth || !$0.containsHealthData) }
        let originals = allFiles.filter { ($0.conversationID == nil || chatIDs.contains($0.conversationID!)) && (includePrivate || $0.allowsConnectedModels) && (includeHealth || !$0.containsHealthData) }
        let notes = try inboxEntries().filter { ($0.conversationID == nil || chatIDs.contains($0.conversationID!)) && (includePrivate || !$0.containsLocalOnlyContext) }
        var documentHistory: [ArtifactRecord] = [], revisions: [ConversationRevision] = [], views: [WorkSurface] = []
        for document in documents { documentHistory += try artifactHistory(document.id).filter { (includePrivate || !$0.containsLocalOnlyContext) && (includeHealth || !$0.containsHealthData) } }
        for chat in chats {
            revisions += try conversationRevisions(chat.id).filter { revision in
                (includeHealth || (!revision.conversation.containsHealthData && !revision.artifacts.contains(where: \.containsHealthData) && !revision.surfaces.contains(where: \.containsHealthData))) && (includePrivate || (!revision.conversation.networkDisabled && !revision.conversation.messages.contains(where: \.containsLocalOnlyContext) && !revision.artifacts.contains(where: \.containsLocalOnlyContext) && !revision.surfaces.contains(where: \.containsLocalOnlyContext)))
            }
            views += try surfaces(conversationID: chat.id).filter { (includePrivate || !$0.containsLocalOnlyContext) && (includeHealth || !$0.containsHealthData) }
        }
        let wantedCaptures = Set(chats.flatMap { $0.messages.flatMap(\.captureIDs) } + notes.flatMap(\.captureIDs) + revisions.flatMap { $0.conversation.messages.flatMap(\.captureIDs) })
        var excludedCaptures = Set(allChats.filter { !chatIDs.contains($0.id) }.flatMap { $0.messages.flatMap(\.captureIDs) })
        for chat in allChats {
            for revision in try conversationRevisions(chat.id) where (!includeHealth && revision.conversation.containsHealthData) || (!includePrivate && (revision.conversation.networkDisabled || revision.conversation.messages.contains(where: \.containsLocalOnlyContext))) {
                excludedCaptures.formUnion(revision.conversation.messages.flatMap(\.captureIDs))
            }
        }
        let photos = try captures().filter { !excludedCaptures.contains($0.id) && ((includePrivate && includeHealth) || wantedCaptures.contains($0.id)) }
        let savedMemories = try memories().filter { (includePrivate || $0.allowsConnectedModels) && ($0.conversationID == nil || chatIDs.contains($0.conversationID!)) && ($0.sourceConversationID == nil || chatIDs.contains($0.sourceConversationID!)) }
        let memoryIDs = Set(savedMemories.map(\.id))
        let memoryHistory = try database.execute("SELECT payload FROM memory_changes ORDER BY created_at").map { try Self.decode(MemoryChange.self, $0[0].data!) }.filter { memoryIDs.contains($0.memoryID) && (includePrivate || ($0.before?.allowsConnectedModels != false && $0.after.allowsConnectedModels)) }
        let viewIDs = Set(views.map(\.id))
        let hasSurfaceHistory = try !database.execute("SELECT 1 FROM sqlite_master WHERE name='surface_history'").isEmpty
        let surfaceHistory = try (hasSurfaceHistory ? database.execute("SELECT payload FROM surface_history") : []).map { try Self.decode(WorkSurface.self, $0[0].data!) }.filter { viewIDs.contains($0.id) && (includePrivate || !$0.containsLocalOnlyContext) && (includeHealth || !$0.containsHealthData) }
        let projects = allProjects.filter { chatIDs.contains($0.sourceConversationID) && (includePrivate || !$0.containsLocalOnlyContext) && (includeHealth || !$0.containsHealthData) }
        var binaries: [ArchiveBinary] = []
        for file in originals { let data = try Data(contentsOf: workspaceFileURL(file.id)); binaries.append(.init(id: file.id, kind: "file", bytes: data.count, checksum: PersonalArchive.checksum(data))) }
        for photo in photos { let data = try imageData(photo.id); binaries.append(.init(id: photo.id, kind: "capture", bytes: data.count, checksum: PersonalArchive.checksum(data))) }
        var drafts: [String: String] = [:], documentDrafts: [String: String] = [:]
        if let data = try? Data(contentsOf: root.appendingPathComponent("drafts.json")), let saved = try? JSONDecoder().decode([String: String].self, from: data), includePrivate { drafts = saved.filter { UUID(uuidString: $0.key).map(chatIDs.contains) == true } }
        if includePrivate { for document in documents { if let draft = try artifactDraftRecord(id: document.id) { documentDrafts[document.id.uuidString] = String(decoding: try Self.encode(draft), as: UTF8.self) } } }
        let manifest = PersonalArchiveManifest(includesPrivateData: includePrivate, includesHealthData: includeHealth, conversations: chats, folders: try folders().filter { folder in chats.contains { $0.folderID == folder.id } }, artifacts: documents, artifactHistory: documentHistory, files: originals, captures: photos, memories: savedMemories, memoryHistory: memoryHistory, inbox: notes, projects: projects, surfaces: views, surfaceHistory: surfaceHistory, revisions: revisions, drafts: drafts, artifactDrafts: documentDrafts, exclusions: ["Account credentials and pairing keys", "Model weights and derived caches", "Connected-folder bookmarks", "Pending approvals and executable task queues", "Recently removed Inbox notes", includePrivate && includeHealth ? "" : "Unreferenced camera captures", includePrivate ? "" : "On-device-only work and unsent drafts", includeHealth ? "" : "Health-derived work"].filter { !$0.isEmpty }, binaries: binaries)
        try PersonalArchive.write(manifest: manifest, to: url) { entry in entry.kind == "capture" ? try imageData(entry.id) : try Data(contentsOf: workspaceFileURL(entry.id)) }
        return try PersonalArchive.inspect(url)
    }
    fileprivate func restoreArchiveRecords(_ manifest: PersonalArchiveManifest) throws {
        guard try conversationSummaries().isEmpty else { throw AssistantError.invalidTool("Restore requires a new isolated library.") }
        // Create optional tables before the atomic data import.
        _ = try projectWorkspaces(); _ = try inboxEntries(); try prepareConversationRevisions()
        try database.execute("CREATE TABLE IF NOT EXISTS artifact_history(id TEXT NOT NULL,revision INTEGER NOT NULL,payload BLOB NOT NULL,PRIMARY KEY(id,revision))")
        try database.execute("CREATE TABLE IF NOT EXISTS surface_history(id TEXT NOT NULL,revision INTEGER NOT NULL,payload BLOB NOT NULL,PRIMARY KEY(id,revision))")
        try database.execute("CREATE TABLE IF NOT EXISTS work_surfaces(id TEXT PRIMARY KEY,conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,payload BLOB NOT NULL)")
        try database.transaction {
            for folder in manifest.folders { try saveFolder(folder) }
            for var chat in manifest.conversations { chat.allowedNetworkDestinations = []; chat.allowedHealthDestinations = []; chat.requiresNetworkReview = true; for index in chat.messages.indices { chat.messages[index].continuation = nil }; chat.recoverInterruptedMessages(); try Self.persist(chat, in: database) }
            for artifact in manifest.artifacts { try saveArtifact(artifact) }
            for item in manifest.artifactHistory { try database.execute("INSERT INTO artifact_history VALUES(?,?,?)", [.text(item.id.uuidString), .integer(Int64(item.revision)), .blob(try Self.encode(item))]) }
            for var file in manifest.files { file.allowsConnectedModels = false; file.allowsWorkspaceSearch = false; try database.execute("INSERT INTO workspace_files VALUES(?,?,?)", [.text(file.id.uuidString), .real(file.createdAt.timeIntervalSince1970), .blob(try Self.encode(file))]) }
            for var memory in manifest.memories { memory.allowsConnectedModels = false; try database.execute("INSERT INTO memories VALUES(?,?,?)", [.text(memory.id.uuidString), .real(memory.updatedAt.timeIntervalSince1970), .blob(try Self.encode(memory))]) }
            for var change in manifest.memoryHistory { change.before?.allowsConnectedModels = false; change.after.allowsConnectedModels = false; try database.execute("INSERT INTO memory_changes VALUES(?,?,?,?,?)", [.text(change.id.uuidString), .text(change.memoryID.uuidString), .real(change.createdAt.timeIntervalSince1970), .text(change.operationID), .blob(try Self.encode(change))]) }
            for note in manifest.inbox { try database.execute("INSERT INTO assistant_inbox VALUES(?,?,?)", [.text(note.id.uuidString), .real(note.createdAt.timeIntervalSince1970), .blob(try Self.encode(note))]) }
            for project in manifest.projects { try database.execute("INSERT INTO project_workspaces VALUES(?,?)", [.text(project.id.uuidString), .blob(try Self.encode(project))]) }
            for surface in manifest.surfaces { try saveSurface(surface) }
            for surface in manifest.surfaceHistory { try database.execute("INSERT INTO surface_history VALUES(?,?,?)", [.text(surface.id.uuidString), .integer(Int64(surface.revision)), .blob(try Self.encode(surface))]) }
            for revision in manifest.revisions { try insertConversationRevision(revision) }
            for (id, draft) in manifest.artifactDrafts { try database.execute("INSERT INTO metadata VALUES(?,?)", [.text("artifact-draft-state:" + id), .text(draft)]) }
        }
        for capture in manifest.captures {
            let folder = root.appendingPathComponent("captures").appendingPathComponent(capture.id.uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Self.encode(capture).write(to: folder.appendingPathComponent("observation.json"), options: .atomic)
        }
        try JSONEncoder().encode(manifest.drafts).write(to: root.appendingPathComponent("drafts.json"), options: .atomic)
    }
    fileprivate func verifyRestoredArchive(_ value: PersonalArchiveManifest) throws {
        guard try conversationSummaries().count == value.conversations.count, try artifacts().count == value.artifacts.count, try workspaceFiles().count == value.files.count, try unfinishedWork().isEmpty else { throw AssistantError.invalidTool("The staged library did not pass verification.") }
        for file in value.files { _ = try workspaceFileURL(file.id) }
        for capture in value.captures { _ = try captureImageURL(capture.id) }
        try rebuildLibraryIndex()
    }
}
