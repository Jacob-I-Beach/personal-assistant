import AssistantCore
import Foundation

extension AppModel {
    @discardableResult
    func captureInbox(text: String, destination: UUID?, handling: InboxHandling, captureIDs: [UUID] = []) async throws -> InboxEntry {
        guard let store else { throw AssistantError.provider("App storage is unavailable.") }
        var localOnly = settings.localOnly
        if let destination {
            let chat = try await store.loadConversation(destination)
            guard chat.archivedAt == nil else { throw AssistantError.invalidTool("Choose an unarchived destination chat.") }
            localOnly = localOnly || chat.networkDisabled
        }
        let entry = InboxEntry(text: text, conversationID: destination, handling: handling, captureIDs: captureIDs, localOnly: localOnly)
        try await store.saveInboxEntry(entry); await refresh()
        if handling == .answerNow { await askAboutInbox(entry) }
        return entry
    }
    func askAboutInbox(_ entry: InboxEntry) async {
        guard !isRunning, let store else { noticeMessage = "Saved in Inbox. Open it when the current task is finished."; return }
        if entry.containsLocalOnlyContext && settings.networkDestination != nil { noticeMessage = "This note was saved for on-device use. Choose an on-device model before asking about it."; return }
        if let id = entry.conversationID {
            guard let summary = histories.first(where: { $0.id == id && $0.archivedAt == nil }) else { noticeMessage = "The destination chat is unavailable. Choose a current destination from Inbox."; return }
            await selectConversation(summary)
        } else { newConversation() }
        guard draft.isEmpty, attachedFileIDs.isEmpty, attachedCaptureIDs.isEmpty else { noticeMessage = "Your existing draft is kept. The captured note remains in Inbox until you finish that draft."; return }
        do {
            try await store.save(conversation)
            draft = entry.text; attachedCaptureIDs = entry.captureIDs; routedInboxID = entry.id
            flushDraft(); showInbox = false; send()
        } catch { errorMessage = error.localizedDescription }
    }
    func finishInboxEntry(_ entry: InboxEntry) async {
        var updated = entry; updated.handledAt = Date()
        do { try await store?.saveInboxEntry(updated); await refresh() } catch { errorMessage = error.localizedDescription }
    }
}
extension InboxHandling {
    var title: String { switch self { case .saveOnly: "Save only"; case .later: "For later"; case .answerNow: "Answer now" } }
}
