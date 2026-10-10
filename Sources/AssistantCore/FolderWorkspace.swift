import Foundation

public struct FolderConnection: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var bookmark: Data
    public var allowsConnectedModels: Bool
    public var allowsEdits: Bool
    public var connectedAt: Date
    public init(id: UUID = UUID(), name: String, bookmark: Data, allowsConnectedModels: Bool = false, allowsEdits: Bool = false) {
        self.id = id; self.name = name; self.bookmark = bookmark
        self.allowsConnectedModels = allowsConnectedModels; self.allowsEdits = allowsEdits; connectedAt = Date()
    }
}
public struct FolderFile: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var workspaceID: UUID
    public var relativePath: String
    public var isDirectory: Bool
    public var byteCount: Int
    public var modifiedAt: Date?
    public init(id: UUID = UUID(), workspaceID: UUID, relativePath: String, isDirectory: Bool, byteCount: Int, modifiedAt: Date? = nil) {
        self.id = id; self.workspaceID = workspaceID; self.relativePath = relativePath; self.isDirectory = isDirectory
        self.byteCount = byteCount; self.modifiedAt = modifiedAt
    }
}
public struct FileEditProposal: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var file: FolderFile
    public var original: String
    public var originalBytes: Data
    public var replacement: String
    public var createdAt: Date
    public var state: String
    public init(file: FolderFile, original: String, replacement: String, originalBytes: Data? = nil) throws {
        guard original.utf8.count <= 128_000, replacement.utf8.count <= 128_000,
              !replacement.contains("\0"), !original.contains("\0"),
              original.components(separatedBy: "\n").count <= 2000, replacement.components(separatedBy: "\n").count <= 2000 else {
            throw AssistantError.invalidTool("Reviewed edits support UTF-8 text up to 128 KB and 2,000 lines; use a new output for larger or binary documents.")
        }
        id = UUID(); self.file = file; self.original = original; self.originalBytes = originalBytes ?? Data(original.utf8)
        self.replacement = replacement; createdAt = Date(); state = "proposed"
    }
    public func validateCurrent(_ data: Data) throws {
        guard data == originalBytes else {
            throw AssistantError.invalidTool("The file changed since it was read. Read it again and propose a new edit; no changes were applied.")
        }
    }
}
public struct TextDiffLine: Equatable, Identifiable, Sendable {
    public enum Kind: String, Sendable { case unchanged, removed, added }
    public var id: Int
    public var kind: Kind
    public var text: String
    public static func compare(before: String, after: String) -> [TextDiffLine] {
        let old = before.components(separatedBy: "\n"), new = after.components(separatedBy: "\n")
        let difference = new.difference(from: old)
        var removed = Set<Int>(), added = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): added.insert(offset)
            }
        }
        var output: [TextDiffLine] = [], i = 0, j = 0
        while i < old.count || j < new.count {
            if i < old.count && removed.contains(i) { output.append(.init(id: output.count, kind: .removed, text: old[i])); i += 1 }
            else if j < new.count && added.contains(j) { output.append(.init(id: output.count, kind: .added, text: new[j])); j += 1 }
            else if i < old.count && j < new.count { output.append(.init(id: output.count, kind: .unchanged, text: old[i])); i += 1; j += 1 }
            else { break }
        }
        return output
    }
}
