import Foundation

/// An autosaved edit is not an authoritative document revision. A legacy draft
/// with an unknown base requires review rather than acquiring today's revision.
public struct ArtifactDraft: Codable, Equatable, Sendable {
    public var text: String
    public var baseRevision: Int?
    public var updatedAt: Date
    public init(text: String, baseRevision: Int?, updatedAt: Date = Date()) {
        self.text = text; self.baseRevision = baseRevision; self.updatedAt = updatedAt
    }
    public func canCommit(over artifact: ArtifactRecord) -> Bool { baseRevision == artifact.revision }
}

extension LocalStore {
    public func artifactDraftRecord(id: UUID) throws -> ArtifactDraft? {
        guard !(try database.execute("SELECT id FROM artifacts WHERE id=?", [.text(id.uuidString)])).isEmpty else { return nil }
        if let value = try database.execute("SELECT value FROM metadata WHERE key=?", [.text("artifact-draft-state:" + id.uuidString)]).first?[0].text {
            return try JSONDecoder().decode(ArtifactDraft.self, from: Data(value.utf8))
        }
        if let legacy = try database.execute("SELECT value FROM metadata WHERE key=?", [.text("artifact-draft:" + id.uuidString)]).first?[0].text {
            return ArtifactDraft(text: legacy, baseRevision: nil)
        }
        return nil
    }
    public func commitArtifactDraft(id: UUID, expectedRevision: Int?, text: String) throws -> ArtifactRecord {
        guard let expectedRevision else { throw AssistantError.provider("This older draft has no saved base revision. Compare it with the saved document before applying it.") }
        return try reviseArtifact(id: id, expectedRevision: expectedRevision, content: text, clearDraft: true)
    }
}
