import AssistantCore
import SwiftUI

struct AssistantInboxView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var navigation: ChatNavigation
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var destination: UUID?
    @State private var handling: InboxHandling = .saveOnly
    @State private var saving = false
    @State private var notice: String?
    var body: some View {
        NavigationStack {
            List {
                Section("Capture a thought") {
                    TextField("Save an idea, a link, or something to handle later", text: $text, axis: .vertical).lineLimit(3...6).accessibilityIdentifier("inbox-note")
                    DisclosureGroup("Destination and handling") {
                    Picker("Destination", selection: $destination) {
                        Text("Inbox").tag(UUID?.none)
                        ForEach(model.histories.filter { $0.archivedAt == nil }) { Text($0.title).tag(Optional($0.id)) }
                    }
                    Picker("What should happen", selection: $handling) { ForEach(InboxHandling.allCases, id: \.self) { Text($0.title).tag($0) } }
                    Text(handling == .saveOnly ? "Keeps the note without asking a model to respond." : handling == .later ? "Keeps this in your waiting work until you choose to ask about it." : "Starts a reply in the chosen chat when the assistant is available.").font(.caption).foregroundStyle(.secondary)
                    }
                    Button(saving ? "Saving…" : handling == .saveOnly ? "Save note" : handling == .later ? "Save for later" : "Start reply") {
                        saving = true
                        Task {
                            defer { saving = false }
                            do { _ = try await model.captureInbox(text: text, destination: destination, handling: handling); text = ""; notice = handling == .saveOnly ? "Saved without a model response." : "Captured." }
                            catch { notice = error.localizedDescription }
                        }
                    }.disabled(saving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("inbox-save")
                    if let notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
                }
                if !model.inbox.isEmpty {
                    Section("Your captures") {
                        ForEach(model.inbox) { entry in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(entry.text).font(.subheadline).textSelection(.enabled)
                                HStack {
                                    Label(entry.handledAt != nil ? "Filed" : entry.handling.title, systemImage: entry.handledAt != nil ? "checkmark.circle" : "tray")
                                    if let id = entry.conversationID, let chat = model.histories.first(where: { $0.id == id }) { Text("· " + chat.title).lineLimit(1) }
                                }.font(.caption).foregroundStyle(.secondary)
                                HStack {
                                    Button("Ask about this") {
                                        Task {
                                            if let id = entry.conversationID, id != model.conversation.id {
                                                guard let chat = model.histories.first(where: { $0.id == id && $0.archivedAt == nil }) else { notice = "This note's conversation is no longer available."; return }
                                                await model.selectConversation(chat)
                                                guard model.conversation.id == id else { return }
                                            }
                                            let ref = ContextReference(kind: .inbox, sourceID: entry.id.uuidString, title: String(entry.text.prefix(80)), conversationID: model.conversation.id, localOnly: entry.containsLocalOnlyContext, snapshot: entry.text)
                                            navigation.compose(ContextualDraftProposal(reference: ref, prompt: "Help me work through this note."), afterDismissal: true)
                                        }
                                    }.disabled(model.isRunning)
                                    if entry.handledAt == nil { Button("Mark handled") { Task { await model.finishInboxEntry(entry) } } }
                                }.font(.caption).buttonStyle(.borderless)
                            }.padding(.vertical, 6)
                        }.onDelete { indices in
                            let ids = indices.map { model.inbox[$0].id }
                            Task { for id in ids { try? await model.store?.removeInboxEntry(id) }; await model.refresh() }
                        }
                    }
                }
            }.scrollDismissesKeyboard(.interactively).navigationTitle("Assistant inbox")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
