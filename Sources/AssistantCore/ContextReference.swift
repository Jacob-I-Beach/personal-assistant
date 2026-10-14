import Foundation

public struct ContextReference: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case surface, artifact, file, capture, project, inbox, calendar, reminder }
    public var kind: Kind
    public var sourceID: String
    public var title: String
    public var conversationID: UUID
    public var revision: Int?
    public var snapshot: String?
    public var containsLocalOnlyContext: Bool
    public var containsHealthData: Bool
    public var id: String { kind.rawValue + ":" + sourceID }
    public init(kind: Kind, sourceID: String, title: String, conversationID: UUID, revision: Int? = nil, localOnly: Bool = false, health: Bool = false, snapshot: String? = nil) {
        self.kind = kind; self.sourceID = sourceID; self.title = String(title.prefix(160)); self.conversationID = conversationID
        self.revision = revision; containsLocalOnlyContext = localOnly; containsHealthData = health
        self.snapshot = snapshot
    }
    /// Titles are UI source data. Only bounded identity/revision metadata is
    /// added to the provider request; actual reads still use permitted tools.
    public var modelReference: JSONValue {
        .object(["kind": .string(kind.rawValue), "id": .string(sourceID), "revision_at_selection": revision.map { .number(Double($0)) } ?? .null, "selected_source_data": snapshot.map(JSONValue.string) ?? .null])
    }
}

public struct ContextualDraftProposal: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let reference: ContextReference
    public let prompt: String
    public init(reference: ContextReference, prompt: String) { self.reference = reference; self.prompt = prompt }
    public func textPreservingExistingDraft(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? prompt : text }
    public func referencesAddingTo(_ existing: [ContextReference], conversationID: UUID) throws -> [ContextReference] {
        guard reference.conversationID == conversationID else { throw AssistantError.provider("This context belongs to the conversation where you selected it. Your current draft was kept.") }
        var result = existing.filter { $0.id != reference.id }; result.append(reference)
        guard result.count <= 8 else { throw AssistantError.provider("Use up to eight selected context items in one message.") }
        return result
    }
}

extension LocalStore {
    public func validateContextReferences(_ references: [ContextReference], conversationID: UUID, remote: Bool) throws -> [ContextReference] {
        guard references.count <= 8, Set(references.map(\.id)).count == references.count else { throw AssistantError.invalidTool("Invalid selected context.") }
        return try references.map { original in
            guard original.conversationID == conversationID, !original.sourceID.isEmpty, original.sourceID.utf8.count <= 1024,
                  (original.snapshot?.utf8.count ?? 0) <= 32_000,
                  original.revision == nil || (1...9_007_199_254_740_991).contains(original.revision!) else { throw AssistantError.invalidTool("The selected context belongs to another conversation or is invalid.") }
            var result = original
            if ![.inbox, .calendar, .reminder].contains(original.kind) { result.snapshot = nil }
            func requireRevision(_ current: Int) throws {
                guard original.revision == current else { throw AssistantError.provider("The selected \(original.kind.rawValue) changed. Refresh or remove its context chip before sending. Your draft is kept.") }
            }
            switch original.kind {
            case .surface:
                guard let value = try surfaces(conversationID: conversationID).first(where: { $0.id.uuidString == original.sourceID }) else { throw AssistantError.invalidTool("This working view is no longer available in this chat.") }
                try requireRevision(value.revision); result.title = value.title
                result.containsLocalOnlyContext = value.containsLocalOnlyContext; result.containsHealthData = value.containsHealthData
            case .artifact:
                guard let value = try readableArtifacts(conversationID: conversationID, workspace: false, remote: false).first(where: { $0.id.uuidString == original.sourceID }) else { throw AssistantError.invalidTool("Open this document's source chat to ask about it.") }
                try requireRevision(value.revision); result.title = value.filename
                result.containsLocalOnlyContext = value.containsLocalOnlyContext; result.containsHealthData = value.containsHealthData
                if value.containsHealthData && value.conversationID != conversationID { throw AssistantError.networkNotAuthorized }
            case .file:
                guard let id = UUID(uuidString: original.sourceID) else { throw AssistantError.invalidTool("Invalid file reference.") }
                let value = try workspaceFile(id)
                guard !value.containsHealthData || value.conversationID == conversationID else { throw AssistantError.networkNotAuthorized }
                result.title = value.filename; result.containsHealthData = value.containsHealthData
                // Explicit attachment follows the existing one-chat consent path.
            case .capture:
                guard let id = UUID(uuidString: original.sourceID) else { throw AssistantError.invalidTool("Invalid photo reference.") }
                _ = try loadCapture(id)
            case .project:
                guard let value = try projectWorkspace(conversationID: conversationID, remote: false), value.id.uuidString == original.sourceID else { throw AssistantError.invalidTool("This project is outside the current chat or folder.") }
                try requireRevision(value.revision); result.title = value.title
                result.containsLocalOnlyContext = value.containsLocalOnlyContext; result.containsHealthData = value.containsHealthData
                guard value.needsContextRebuild != true else { throw AssistantError.provider("Review this project's changed context before attaching it to a new request.") }
            case .inbox:
                guard let value = try inboxEntries().first(where: { $0.id.uuidString == original.sourceID }), value.conversationID == nil || value.conversationID == conversationID else { throw AssistantError.invalidTool("This Inbox note belongs to another conversation.") }
                result.containsLocalOnlyContext = value.containsLocalOnlyContext
                result.snapshot = value.text
            case .calendar, .reminder:
                // Opaque native identifiers do not grant Calendar access. The
                // existing native tool re-reads the selected source and version.
                break
            }
            guard !remote || !result.containsLocalOnlyContext else { throw AssistantError.networkNotAuthorized }
            return result
        }
    }
}
