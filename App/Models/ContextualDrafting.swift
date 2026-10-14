import AssistantCore
import Foundation

extension AppModel {
    func attachSelectedFiles(_ ids: [UUID], to owner: UUID) async throws {
        guard owner == conversation.id, !isRunning, let store else { throw AssistantError.provider("The conversation changed. No files were added to another draft.") }
        var unique: [UUID] = []
        for id in ids where !unique.contains(id) { unique.append(id) }
        guard Set(attachedFileIDs + unique).count <= 20 else { throw AssistantError.provider("Attach up to twenty files in one message.") }
        var includesHealth = false
        for id in unique {
            let file = try await store.workspaceFile(id)
            guard !file.containsHealthData || file.conversationID == owner else { throw AssistantError.networkNotAuthorized }
            includesHealth = includesHealth || file.containsHealthData
        }
        guard owner == conversation.id, !isRunning else { throw AssistantError.provider("The conversation changed. Your original selection was not attached elsewhere.") }
        for id in unique where !attachedFileIDs.contains(id) { attachedFileIDs.append(id) }
        draftContainsHealthData = draftContainsHealthData || includesHealth; flushDraft()
    }
    func offerContextualDraft(reference: ContextReference, prompt: String) async {
        guard !isRunning, nativeAction == nil, let store else { noticeMessage = "Finish the current response or review before adding this context."; return }
        do {
            let validated = try await store.validateContextReferences([reference], conversationID: conversation.id, remote: false)[0]
            guard conversation.id == reference.conversationID, !isRunning, nativeAction == nil else { throw AssistantError.provider("The active conversation or review changed. Your draft was kept.") }
            let proposal = ContextualDraftProposal(reference: validated, prompt: prompt)
            if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachedFileIDs.isEmpty || !attachedCaptureIDs.isEmpty || !draftContextReferences.isEmpty {
                pendingContextualDraft = proposal
            } else { try applyContextualDraft(proposal) }
        } catch { noticeMessage = error.localizedDescription }
    }
    func acceptContextualDraft(_ selected: ContextualDraftProposal? = nil) {
        guard let proposal = selected ?? pendingContextualDraft else { return }; pendingContextualDraft = nil
        do { try applyContextualDraft(proposal) } catch { noticeMessage = error.localizedDescription }
    }
    private func applyContextualDraft(_ proposal: ContextualDraftProposal) throws {
        guard !isRunning, nativeAction == nil else { throw AssistantError.busy }
        let references = try proposal.referencesAddingTo(draftContextReferences, conversationID: conversation.id)
        draft = proposal.textPreservingExistingDraft(draft)
        draftContextReferences = references
        if proposal.reference.kind == .file, let id = UUID(uuidString: proposal.reference.sourceID) { attachFile(id) }
        if proposal.reference.kind == .capture, let id = UUID(uuidString: proposal.reference.sourceID) { attach(id) }
        if proposal.reference.kind == .inbox, let entry = inbox.first(where: { $0.id.uuidString == proposal.reference.sourceID }) {
            for id in entry.captureIDs { attach(id) }
        }
        if proposal.reference.containsHealthData { draftContainsHealthData = true; libraryContainsHealthData = true }
        noticeMessage = "Context added to your draft. Send when you are ready."
        composerFocusRequest = UUID(); flushDraft()
    }
    func removeDraftContext(_ id: String) { draftContextReferences.removeAll { $0.id == id }; flushDraft() }
    func refreshDraftContext(_ reference: ContextReference) async {
        guard let store, !isRunning else { return }
        do {
            var latest = reference
            switch reference.kind {
            case .surface: latest.revision = try await store.surfaces(conversationID: conversation.id).first(where: { $0.id.uuidString == reference.sourceID })?.revision
            case .artifact: latest.revision = try await store.artifacts(conversationID: conversation.id).first(where: { $0.id.uuidString == reference.sourceID })?.revision
            case .project: latest.revision = try await store.projectWorkspace(conversationID: conversation.id, remote: false)?.revision
            default: break
            }
            let validated = try await store.validateContextReferences([latest], conversationID: conversation.id, remote: false)[0]
            guard !isRunning, let index = draftContextReferences.firstIndex(where: { $0.id == reference.id }), conversation.id == reference.conversationID else { return }
            draftContextReferences[index] = validated; draftContainsHealthData = draftContainsHealthData || validated.containsHealthData; flushDraft()
        } catch { noticeMessage = error.localizedDescription }
    }
}
