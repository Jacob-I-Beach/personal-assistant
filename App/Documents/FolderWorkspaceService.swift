import AssistantCore
import Foundation

/// Bookmarks and edit snapshots stay in Application Support. Model-facing results never contain them.
actor FolderWorkspaceService {
    private static let editableExtensions: Set<String> = ["", "txt", "md", "markdown", "csv", "tsv", "json", "jsonl", "xml", "html", "htm", "css", "js", "ts", "py", "swift", "yaml", "yml", "log", "sql", "c", "h", "cpp", "rs", "sh", "toml", "ics", "vcf", "svg"]
    private struct Snapshot: Codable, Sendable { var fileID: UUID; var data: Data; var createdAt: Date }
    private struct State: Codable {
        var connections: [FolderConnection] = []
        var files: [FolderFile] = []
        var snapshots: [String: Snapshot] = [:]
        var edits: [FileEditProposal] = []
    }
    private let stateURL: URL
    private let requiresSecurityScope: Bool
    private var state: State
    init(storage: URL, requiresSecurityScope: Bool = true) throws {
        stateURL = storage.appendingPathComponent("connected-folders.json")
        self.requiresSecurityScope = requiresSecurityScope
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        state = FileManager.default.fileExists(atPath: stateURL.path) ? try JSONDecoder().decode(State.self, from: Data(contentsOf: stateURL)) : State()
    }
    func connections() -> [FolderConnection] { state.connections }
    func fileRecord(_ id: UUID) throws -> FolderFile {
        guard let entry = state.files.first(where: { $0.id == id }) else { throw AssistantError.invalidTool("List or search the folder before using this file.") }
        return entry
    }
    func pendingEdits(_ workspaceIDs: Set<UUID>) -> [FileEditProposal] {
        state.edits.filter { workspaceIDs.contains($0.file.workspaceID) && $0.state == "proposed" }
    }
    func history(_ workspaceID: UUID) -> [FileEditProposal] {
        state.edits.filter { $0.file.workspaceID == workspaceID }.sorted { $0.createdAt > $1.createdAt }
    }
    func metadata(_ id: UUID, remote: Bool) throws -> FolderFile {
        var entry = try fileRecord(id)
        try withRoot(entry.workspaceID, remote: remote, write: false) { root in
            let url = try WorkspacePath.resolve(entry.relativePath, inside: root)
            try coordinate(url, writing: false) { url in
                let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey])
                entry.byteCount = values.fileSize ?? 0; entry.modifiedAt = values.contentModificationDate; entry.isDirectory = values.isDirectory == true
            }
        }
        return entry
    }
    func search(_ id: UUID, query: String, remote: Bool) throws -> (matches: [(FolderFile, String)], scanned: Int, limited: Bool) {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty, query.count <= 200 else { throw AssistantError.invalidTool("Use a short search query.") }
        var scanned = 0, bytesRead = 0, matches: [(FolderFile, String)] = [], limited = false
        try withRoot(id, remote: remote, write: false) { root in
            try coordinate(root, writing: false) { root in
                let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
                guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { throw AssistantError.invalidTool("The folder provider is unavailable.") }
                for case let url as URL in enumerator {
                    try Task.checkCancellation()
                    scanned += 1
                    if scanned > 1000 || matches.count >= 30 { limited = true; break }
                    let relative = url.pathComponents.dropFirst(root.pathComponents.count).joined(separator: "/")
                    guard (try? WorkspacePath.resolve(relative, inside: root)) != nil else { enumerator.skipDescendants(); continue }
                    let values = try url.resourceValues(forKeys: keys)
                    guard values.isSymbolicLink != true else { enumerator.skipDescendants(); continue }
                    if values.isDirectory == true { continue }
                    guard values.isRegularFile == true else { continue }
                    var snippet = "", haystack = relative.lowercased()
                    let ext = url.pathExtension.lowercased()
                    if Self.editableExtensions.contains(ext), bytesRead < 2 * 1024 * 1024 {
                        let handle = try FileHandle(forReadingFrom: url)
                        defer { try? handle.close() }
                        let bytes = try handle.read(upToCount: 32_768) ?? Data(); bytesRead += bytes.count
                        if let text = String(data: bytes, encoding: .utf8), !text.contains("\0") {
                            haystack += "\n" + text.lowercased()
                            if let range = text.range(of: terms[0], options: .caseInsensitive) {
                                let start = text.index(range.lowerBound, offsetBy: -80, limitedBy: text.startIndex) ?? text.startIndex
                                snippet = String(text[start...].prefix(300))
                            }
                            if (values.fileSize ?? 0) > bytes.count { limited = true }
                        }
                    } else { limited = true }
                    guard terms.allSatisfy({ haystack.contains($0) }) else { continue }
                    let entry = FolderFile(id: state.files.first { $0.workspaceID == id && $0.relativePath == relative }?.id ?? UUID(), workspaceID: id,
                                           relativePath: relative, isDirectory: false, byteCount: values.fileSize ?? 0, modifiedAt: values.contentModificationDate)
                    matches.append((entry, snippet))
                }
            }
        }
        for (entry, _) in matches { state.files.removeAll { $0.id == entry.id }; state.files.append(entry) }
        try persist()
        return (matches, min(scanned, 1000), limited)
    }
    func connect(_ url: URL) throws -> FolderConnection {
        let scoped = url.startAccessingSecurityScopedResource()
        guard scoped || isOwnedDocumentFolder(url) || !requiresSecurityScope else { throw AssistantError.provider("Access to this folder was not granted. Choose it again in Files.") }
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let properties = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard properties.isDirectory == true, properties.isSymbolicLink != true else {
            throw AssistantError.provider("Choose a folder, not a single document.")
        }
        let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        if let index = state.connections.firstIndex(where: {
            var stale = false
            return (try? URL(resolvingBookmarkData: $0.bookmark, bookmarkDataIsStale: &stale))?.standardizedFileURL == url.standardizedFileURL
        }) {
            state.connections[index].bookmark = bookmark; state.connections[index].name = url.lastPathComponent
            try persist(); return state.connections[index]
        }
        let entry = FolderConnection(name: url.lastPathComponent, bookmark: bookmark)
        state.connections.append(entry); try persist()
        return entry
    }
    func setAccess(_ id: UUID, connected: Bool? = nil, edits: Bool? = nil) throws {
        guard let index = state.connections.firstIndex(where: { $0.id == id }) else { throw AssistantError.provider("The folder was disconnected.") }
        if let connected { state.connections[index].allowsConnectedModels = connected }
        if let edits { state.connections[index].allowsEdits = edits }
        try persist()
    }
    func disconnect(_ id: UUID) throws {
        let files = Set(state.files.filter { $0.workspaceID == id }.map(\.id))
        state.connections.removeAll { $0.id == id }; state.files.removeAll { $0.workspaceID == id }
        state.snapshots = state.snapshots.filter { !files.contains($0.value.fileID) }
        state.edits.removeAll { $0.file.workspaceID == id }
        try persist()
    }
    func list(_ id: UUID, folderID: UUID? = nil, offset: Int = 0, remote: Bool) throws -> (files: [FolderFile], next: Int?) {
        guard offset >= 0, offset <= 5000 else { throw AssistantError.invalidTool("Invalid folder cursor.") }
        let relative: String?
        if let folderID {
            let folder = try file(folderID, workspace: id)
            guard folder.isDirectory else { throw AssistantError.invalidTool("That item is not a folder.") }
            relative = folder.relativePath
        } else { relative = nil }
        let entries: [FolderFile] = try withRoot(id, remote: remote, write: false) { root in
            let directory = try relative.map { try WorkspacePath.resolve($0, inside: root) } ?? root
            return try coordinate(directory, writing: false) { directory in
                let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles])
                guard urls.count <= 5000 else { throw AssistantError.invalidTool("This folder has more than 5,000 immediate entries. Connect a smaller subfolder.") }
                return try urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }.compactMap { url in
                    let path = (relative.map { $0 + "/" } ?? "") + url.lastPathComponent
                    guard (try? WorkspacePath.resolve(path, inside: root)) != nil else { return nil }
                    let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
                    guard values.isSymbolicLink != true, values.isDirectory == true || values.isRegularFile == true else { return nil }
                    let existing = state.files.first { $0.workspaceID == id && $0.relativePath == path }
                    return FolderFile(id: existing?.id ?? UUID(), workspaceID: id, relativePath: path, isDirectory: values.isDirectory == true,
                                      byteCount: values.fileSize ?? 0, modifiedAt: values.contentModificationDate)
                }
            }
        }
        for entry in entries {
            state.files.removeAll { $0.id == entry.id }; state.files.append(entry)
        }
        guard state.files.count <= 10_000 else { throw AssistantError.invalidTool("The folder index reached its 10,000-entry limit. Disconnect folders you no longer need.") }
        try persist()
        let page = Array(entries.dropFirst(offset).prefix(50))
        return (page, offset + page.count < entries.count ? offset + page.count : nil)
    }
    func read(_ fileID: UUID, remote: Bool) throws -> (file: FolderFile, data: Data, version: String) {
        guard let entry = state.files.first(where: { $0.id == fileID }), !entry.isDirectory else { throw AssistantError.invalidTool("List the folder and select a file first.") }
        let data = try withRoot(entry.workspaceID, remote: remote, write: false) { root in
            let url = try WorkspacePath.resolve(entry.relativePath, inside: root)
            return try coordinate(url, writing: false) { coordinated in
                _ = try WorkspacePath.resolve(entry.relativePath, inside: root)
                let size = try coordinated.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
                guard size <= 25 * 1024 * 1024 else { throw AssistantError.invalidTool("This file exceeds the 25 MB reading limit.") }
                let data = try readBounded(coordinated, maximum: 25 * 1024 * 1024)
                guard data.count <= 25 * 1024 * 1024 else { throw AssistantError.invalidTool("The file grew beyond the reading limit.") }
                return data
            }
        }
        let version = UUID().uuidString
        if Self.editableExtensions.contains((entry.relativePath as NSString).pathExtension.lowercased()),
           data.count <= 128_000, let text = String(data: data, encoding: .utf8), !text.contains("\0") {
            if state.snapshots.count >= 16, let oldest = state.snapshots.min(by: { $0.value.createdAt < $1.value.createdAt })?.key { state.snapshots.removeValue(forKey: oldest) }
            state.snapshots[version] = Snapshot(fileID: fileID, data: data, createdAt: Date()); try persist()
        }
        return (entry, data, version)
    }
    func propose(fileID: UUID, version: String, replacement: String, remote: Bool) throws -> FileEditProposal {
        guard let entry = state.files.first(where: { $0.id == fileID }),
              let snapshot = state.snapshots[version], snapshot.fileID == fileID,
              let text = String(data: snapshot.data, encoding: .utf8) else { throw AssistantError.invalidTool("Read this UTF-8 text file again to obtain a current version token before editing.") }
        _ = try connection(entry.workspaceID, remote: remote, write: true)
        try validateTextContent(entry.relativePath, content: replacement)
        let proposal = try FileEditProposal(file: entry, original: text, replacement: replacement, originalBytes: snapshot.data)
        state.edits.removeAll { $0.state == "proposed" && $0.file.id == fileID }
        guard state.edits.count < 64 else { throw AssistantError.invalidTool("The saved edit history is full. Disconnect and reconnect a folder after keeping any recovery copies you need.") }
        state.edits.append(proposal); try persist()
        return proposal
    }
    func proposal(_ id: UUID, remote: Bool) throws -> FileEditProposal {
        guard let proposal = state.edits.first(where: { $0.id == id }) else { throw AssistantError.invalidTool("That edit proposal is unavailable.") }
        _ = try connection(proposal.file.workspaceID, remote: remote, write: true)
        return proposal
    }
    /// Called only after the native review confirms this exact proposal ID.
    func apply(_ id: UUID, remote: Bool) throws -> FileEditProposal {
        var proposal = try proposal(id, remote: remote)
        guard proposal.state != "cancelled" else { throw AssistantError.invalidTool("The user cancelled this proposal. Do not retry it.") }
        let desired = Data(proposal.replacement.utf8)
        try withRoot(proposal.file.workspaceID, remote: remote, write: true) { root in
            let url = try WorkspacePath.resolve(proposal.file.relativePath, inside: root)
            try coordinate(url, writing: true) { coordinated in
                _ = try WorkspacePath.resolve(proposal.file.relativePath, inside: root)
                let current = try readBounded(coordinated, maximum: 128_000)
                if current == desired { return } // Reconcile an earlier successful/unknown write without duplicating it.
                guard proposal.state != "applied" else { throw AssistantError.invalidTool("The file changed after this edit was applied; read it again instead of repeating the old edit.") }
                try proposal.validateCurrent(current)
                try Task.checkCancellation()
                try desired.write(to: coordinated, options: .atomic)
                guard try readBounded(coordinated, maximum: 128_000) == desired else { throw AssistantError.invalidTool("The provider did not confirm the expected file contents. Read the file before retrying.") }
            }
        }
        proposal.state = "applied"
        state.edits.removeAll { $0.id == id }; state.edits.append(proposal); try persist()
        return proposal
    }
    func cancelProposal(_ id: UUID) throws {
        if let index = state.edits.firstIndex(where: { $0.id == id }) { state.edits[index].state = "cancelled"; try persist() }
    }
    func create(_ id: UUID, folderID: UUID? = nil, filename: String, content: String, remote: Bool) throws -> FolderFile {
        try WorkspaceFile.validateFilename(filename)
        guard content.utf8.count <= 128_000, !content.contains("\0"),
              Self.editableExtensions.contains((filename as NSString).pathExtension.lowercased()) else {
            throw AssistantError.invalidTool("Create a UTF-8 text/code/CSV/JSON file up to 128 KB. Use the artifact/PDF tools for other formats.")
        }
        let data = Data(content.utf8)
        try validateTextContent(filename, content: content)
        var parentPath: String?
        if let folderID {
            let parent = try file(folderID, workspace: id)
            guard parent.isDirectory else { throw AssistantError.invalidTool("The chosen destination is not a folder.") }
            parentPath = parent.relativePath
        }
        let relative = (parentPath.map { $0 + "/" } ?? "") + filename
        try withRoot(id, remote: remote, write: true) { root in
            let parent = try parentPath.map { try WorkspacePath.resolve($0, inside: root) } ?? root
            try coordinate(parent, writing: true) { _ in
                let url = try WorkspacePath.resolve(relative, inside: root, allowMissingLeaf: true)
                if FileManager.default.fileExists(atPath: url.path) {
                    guard (try? readBounded(url, maximum: 128_000)) == data else { throw AssistantError.invalidTool("A different file already uses this name. Choose a new name or read it and propose a reviewed edit.") }
                    return
                }
                try Task.checkCancellation()
                try data.write(to: url, options: .withoutOverwriting)
                guard try Data(contentsOf: url) == data else { throw AssistantError.invalidTool("The new file could not be verified. Read it before retrying.") }
            }
        }
        let entry = FolderFile(id: state.files.first { $0.workspaceID == id && $0.relativePath == relative }?.id ?? UUID(),
                               workspaceID: id, relativePath: relative, isDirectory: false, byteCount: data.count, modifiedAt: Date())
        state.files.removeAll { $0.id == entry.id }; state.files.append(entry); try persist()
        return entry
    }
    private func file(_ id: UUID, workspace: UUID) throws -> FolderFile {
        guard let entry = state.files.first(where: { $0.id == id && $0.workspaceID == workspace }) else { throw AssistantError.invalidTool("That item is outside this folder's scope.") }
        return entry
    }
    private func connection(_ id: UUID, remote: Bool, write: Bool) throws -> FolderConnection {
        guard let connection = state.connections.first(where: { $0.id == id }) else { throw AssistantError.invalidTool("The folder was disconnected.") }
        guard !remote || connection.allowsConnectedModels else { throw AssistantError.invalidTool("This folder is available only to on-device models. The user can change its access in Library > Connected folders.") }
        guard !write || connection.allowsEdits else { throw AssistantError.invalidTool("Editing is disabled for this folder. The user can enable it in the folder's access settings.") }
        return connection
    }
    private func withRoot<T>(_ id: UUID, remote: Bool, write: Bool, body: (URL) throws -> T) throws -> T {
        let entry = try connection(id, remote: remote, write: write)
        var stale = false
        let root = try URL(resolvingBookmarkData: entry.bookmark, bookmarkDataIsStale: &stale)
        guard !stale else { throw AssistantError.invalidTool("The folder's saved access is stale. Reconnect it from Library.") }
        let scoped = root.startAccessingSecurityScopedResource()
        guard scoped || isOwnedDocumentFolder(root) || !requiresSecurityScope else { throw AssistantError.invalidTool("Folder access was revoked or the provider is unavailable. Reconnect the folder from Library.") }
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }
        try Task.checkCancellation()
        return try body(root)
    }
    private func coordinate<T>(_ url: URL, writing: Bool, body: (URL) throws -> T) throws -> T {
        var error: NSError?, result: Result<T, any Error>?
        let accessor: (URL) -> Void = { coordinated in
            result = Result {
                guard coordinated.resolvingSymlinksInPath().standardizedFileURL == url.resolvingSymlinksInPath().standardizedFileURL else {
                    throw AssistantError.invalidTool("The file moved while access was being coordinated. List the folder again before continuing.")
                }
                return try body(coordinated)
            }
        }
        if writing { NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &error, byAccessor: accessor) }
        else { NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error, byAccessor: accessor) }
        if let error { throw error }
        guard let result else { throw AssistantError.provider("The file provider did not complete the operation.") }
        return try result.get()
    }
    private func persist() throws {
        try JSONEncoder().encode(state).write(to: stateURL, options: .atomic)
    }
    private func validateTextContent(_ filename: String, content: String) throws {
        let ext = (filename as NSString).pathExtension.lowercased()
        if ext == "json" { _ = try JSONValue.parse(content) }
        if ext == "csv", let value = try? JSONValue.parse(content), value.arrayValue != nil || value.objectValue != nil {
            throw AssistantError.invalidTool("Use CSV rows, not JSON renamed as a CSV file.")
        }
    }
    private func isOwnedDocumentFolder(_ url: URL) -> Bool {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return false }
        let root = documents.resolvingSymlinksInPath().pathComponents, value = url.resolvingSymlinksInPath().pathComponents
        return value.count >= root.count && Array(value.prefix(root.count)) == root
    }
    private func readBounded(_ url: URL, maximum: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while let chunk = try handle.read(upToCount: min(1_048_576, maximum + 1 - data.count)), !chunk.isEmpty {
            try Task.checkCancellation()
            data.append(chunk)
            guard data.count <= maximum else { throw AssistantError.invalidTool("The file exceeds the reading limit.") }
        }
        return data
    }
}
