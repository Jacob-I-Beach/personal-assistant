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
    public enum Preview: String, Sendable { case textAvailable, originalNeedsCheck, interactive }
    public let preview: Preview
    public let savedLocation: String
    public let originTurnID: UUID?
    public let restrictedDiscovery: Bool
    public let updatedAt: Date
    public let bytes: Int
    public let isInput: Bool
    public let localOnly: Bool
    public let health: Bool
    public init(_ value: ArtifactRecord, conversation: Conversation? = nil) {
        savedLocation = "On this iPhone · Library"; originTurnID = Self.origin(callID: value.sourceCallID, conversation: conversation); preview = .textAvailable; restrictedDiscovery = false
        id = value.id; kind = .document; title = value.filename; conversationID = value.conversationID; sourceCallID = value.lastMutationCallID ?? value.sourceCallID; revision = value.revision; updatedAt = value.updatedAt ?? value.createdAt; bytes = value.content.utf8.count; isInput = false; localOnly = value.containsLocalOnlyContext; health = value.containsHealthData
    }
    public init(_ value: WorkspaceFile, conversation: Conversation? = nil) {
        savedLocation = "On this iPhone · Library"; originTurnID = conversation.flatMap { chat in chat.messages.first(where: { $0.isRequest && $0.fileIDs.contains(value.id) })?.id }; preview = .originalNeedsCheck; restrictedDiscovery = !value.allowsConnectedModels
        id = value.id; kind = value.mediaType.hasPrefix("image/") ? .image : .file; title = value.filename; conversationID = value.conversationID; sourceCallID = nil; revision = nil; updatedAt = value.createdAt; bytes = value.byteCount; isInput = value.conversationID == nil; localOnly = false; health = value.containsHealthData
    }
    public init(_ value: WorkSurface, conversation: Conversation? = nil) {
        savedLocation = "Source conversation on this iPhone"; originTurnID = Self.origin(callID: value.sourceCallID, conversation: conversation); preview = .interactive; restrictedDiscovery = false
        id = value.id; kind = .surface; title = value.title; conversationID = value.conversationID; sourceCallID = value.lastMutationCallID ?? value.sourceCallID; revision = value.revision; updatedAt = value.updatedAt; bytes = 0; isInput = false; localOnly = value.containsLocalOnlyContext; health = value.containsHealthData
    }
    private static func origin(callID: String?, conversation: Conversation?) -> UUID? {
        guard let callID, let conversation, let index = conversation.messages.firstIndex(where: { $0.toolCalls.contains { $0.id == callID } }) else { return nil }
        return conversation.messages.prefix(index + 1).last(where: \.isRequest)?.id
    }

}
