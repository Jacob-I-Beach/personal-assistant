import Foundation

/// Presentation-only projection of an existing object. It creates no new
/// identity or permission, and resolves the latest record at every entry point.
public struct OutputPresentation: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable { case document, file, image, surface }
    public let id: UUID
    public let kind: Kind
    public let title: String
    public let conversationID: UUID?
    public let sourceCallID: String?
    public let revision: Int?
    public let updatedAt: Date
    public let bytes: Int
    public let isInput: Bool
    public let localOnly: Bool
    public let health: Bool
    public init(_ value: ArtifactRecord) {
        id = value.id; kind = .document; title = value.filename; conversationID = value.conversationID; sourceCallID = value.lastMutationCallID ?? value.sourceCallID; revision = value.revision; updatedAt = value.updatedAt ?? value.createdAt; bytes = value.content.utf8.count; isInput = false; localOnly = value.containsLocalOnlyContext; health = value.containsHealthData
    }
    public init(_ value: WorkspaceFile) {
        id = value.id; kind = value.mediaType.hasPrefix("image/") ? .image : .file; title = value.filename; conversationID = value.conversationID; sourceCallID = nil; revision = nil; updatedAt = value.createdAt; bytes = value.byteCount; isInput = value.conversationID == nil; localOnly = !value.allowsConnectedModels; health = value.containsHealthData
    }
    public init(_ value: WorkSurface) {
        id = value.id; kind = .surface; title = value.title; conversationID = value.conversationID; sourceCallID = value.lastMutationCallID ?? value.sourceCallID; revision = value.revision; updatedAt = value.updatedAt; bytes = 0; isInput = false; localOnly = value.containsLocalOnlyContext; health = value.containsHealthData
    }
}
