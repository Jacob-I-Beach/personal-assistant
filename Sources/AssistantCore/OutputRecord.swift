import Foundation

public struct OutputRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var filename: String
    public var byteCount: Int
    public var conversationID: UUID
    public var createdAt: Date
    public var verifiedAt: Date?
    public var status: String
    public var warning: String?
    public var location: String { "Files > On My iPhone > Personal Assistant > Outputs > \(filename)" }
}

extension LocalStore {
    public func outputRecord(_ id: UUID) throws -> OutputRecord? {
        guard let text = try database.execute("SELECT value FROM metadata WHERE key = ?", [.text("output:" + id.uuidString)]).first?[0].text else { return nil }
        return try JSONDecoder().decode(OutputRecord.self, from: Data(text.utf8))
    }
    public func outputRecords() throws -> [OutputRecord] {
        try database.execute("SELECT value FROM metadata WHERE key LIKE 'output:%'").compactMap {
            guard let text = $0[0].text else { return nil }
            return try? JSONDecoder().decode(OutputRecord.self, from: Data(text.utf8))
        }.sorted { $0.createdAt > $1.createdAt }
    }
    /// Publish one user-facing copy. Repeating the same identity does not overwrite a user's Files edits.
    public func publishOutput(id: UUID, filename: String, data: Data, conversationID: UUID) throws -> OutputRecord? {
        guard let outputsRoot else { return nil }
        try WorkspaceFile.validateFilename(filename)
        guard data.count <= 25 * 1024 * 1024 else { throw AssistantError.invalidTool("The output exceeds the 25 MB file limit.") }
        if var previous = try outputRecord(id) {
            if previous.status == "writing" {
                let url = try WorkspacePath.resolve(previous.filename, inside: outputsRoot)
                previous.status = (try? Data(contentsOf: url)) == data ? "saved_local" : "needs_attention"
                previous.verifiedAt = previous.status == "saved_local" ? Date() : nil
                previous.warning = previous.status == "saved_local" ? nil : "A previous save was interrupted. The original remains in Library; the existing copy was not overwritten."
                try storeOutput(previous)
            }
            return previous
        }
        try FileManager.default.createDirectory(at: outputsRoot, withIntermediateDirectories: true)
        let ext = (filename as NSString).pathExtension
        let stem = (filename as NSString).deletingPathExtension
        var selected: String?
        for number in 1...1000 {
            let candidate = number == 1 ? filename : "\(String(stem.prefix(120))) (\(number))" + (ext.isEmpty ? "" : ".\(ext)")
            let url = try WorkspacePath.resolve(candidate, inside: outputsRoot, allowMissingLeaf: true)
            if !FileManager.default.fileExists(atPath: url.path) { selected = candidate; break }
        }
        guard let selected else { throw AssistantError.invalidTool("Too many output files use this name. Choose another filename.") }
        let url = try WorkspacePath.resolve(selected, inside: outputsRoot, allowMissingLeaf: true)
        var record = OutputRecord(id: id, filename: selected, byteCount: data.count, conversationID: conversationID, createdAt: Date(), status: "writing")
        try storeOutput(record)
        do {
            try data.write(to: url, options: .withoutOverwriting)
            guard try Data(contentsOf: url) == data else { throw AssistantError.invalidTool("The saved copy did not match the generated file.") }
            record.status = "saved_local"; record.verifiedAt = Date()
        } catch {
            record.status = "needs_attention"
            record.warning = "The original is in Library, but its Files copy could not be verified. Export the original to try again."
        }
        try storeOutput(record)
        return record
    }
    private func storeOutput(_ record: OutputRecord) throws {
        let text = String(decoding: try JSONEncoder().encode(record), as: UTF8.self)
        try database.execute("INSERT INTO metadata(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                             [.text("output:" + record.id.uuidString), .text(text)])
    }
}

public enum WorkspacePath {
    /// Resolve only a relative path under an explicitly supplied root, rejecting symlink components.
    public static func resolve(_ path: String, inside root: URL, allowMissingLeaf: Bool = false) throws -> URL {
        guard !path.isEmpty, path.utf8.count <= 1024, !path.contains("\\"), !path.hasPrefix("/") else {
            throw AssistantError.invalidTool("Use a relative path inside the selected folder.")
        }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count <= 20 else { throw AssistantError.invalidTool("This folder path is too deep.") }
        var current = root.standardizedFileURL
        guard (try? FileManager.default.attributesOfItem(atPath: current.path)[.type] as? FileAttributeType) == .typeDirectory else {
            throw AssistantError.invalidTool("The selected root is not an accessible folder.")
        }
        let canonicalRoot = current.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        for (index, part) in parts.enumerated() {
            try WorkspaceFile.validateFilename(part)
            current.appendPathComponent(part)
            let exists = FileManager.default.fileExists(atPath: current.path)
            if exists {
                let info = try FileManager.default.attributesOfItem(atPath: current.path)
                guard info[.type] as? FileAttributeType != .typeSymbolicLink else { throw AssistantError.invalidTool("Linked paths are outside the supported folder scope.") }
                if info[.type] as? FileAttributeType == .typeRegular, let links = info[.referenceCount] as? NSNumber, links.intValue > 1 {
                    throw AssistantError.invalidTool("Hard-linked files are outside the supported folder scope.")
                }
                if index < parts.count - 1, info[.type] as? FileAttributeType != .typeDirectory {
                    throw AssistantError.invalidTool("A path component is not a folder.")
                }
            } else if !(allowMissingLeaf && index == parts.count - 1) {
                throw AssistantError.invalidTool("The selected file or folder is no longer available.")
            }
            let resolved = current.resolvingSymlinksInPath().standardizedFileURL.pathComponents
            guard resolved.count > canonicalRoot.count, Array(resolved.prefix(canonicalRoot.count)) == canonicalRoot else {
                throw AssistantError.invalidTool("The requested path leaves the selected folder.")
            }
        }
        return current
    }
}
