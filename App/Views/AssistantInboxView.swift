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
    @State private var query = ""
    @State private var filter = "Unhandled"
    @State private var removed: [InboxEntry] = []
    @State private var projects: [ProjectWorkspace] = []
    private var visible: [InboxEntry] { model.inbox.filter { (filter == "All" || (filter == "Filed" ? $0.handledAt != nil : $0.handledAt == nil)) && (query.isEmpty || $0.text.localizedCaseInsensitiveContains(query)) } }
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
                        Picker("Show notes", selection: $filter) { ForEach(["Unhandled", "Filed", "All"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented)
                        if visible.isEmpty { Text("No notes match this view.").foregroundStyle(.secondary) }
                        ForEach(visible) { entry in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(entry.text).font(.subheadline).textSelection(.enabled)
                                Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
                                Menu("Move note") {
                                    Button("Inbox") { Task { await move(entry, to: nil) } }
                                    ForEach(projects) { project in Button("Project: " + project.title) { Task { await move(entry, to: project.sourceConversationID) } } }
                                    ForEach(model.histories.filter { $0.archivedAt == nil }) { chat in Button(chat.title) { Task { await move(entry, to: chat.id) } } }
                                }.font(.caption).frame(minHeight: 44)
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
                            let ids = indices.map { visible[$0].id }
                            Task { do { for id in ids { try await model.store?.removeInboxEntry(id) }; await model.refresh(); removed = try await model.store?.deletedInboxEntries() ?? []; notice = "Note removed. Restore it from Recently removed." } catch { notice = error.localizedDescription } }
                        }
                    }
                }
                if !removed.isEmpty { Section { DisclosureGroup("Recently removed") {
                    ForEach(removed) { entry in HStack { Text(entry.text).lineLimit(2); Spacer(); Button("Restore") { Task { do { try await model.store?.restoreInboxEntry(entry.id); await model.refresh(); removed = try await model.store?.deletedInboxEntries() ?? [] } catch { notice = error.localizedDescription } } }.frame(minHeight: 44) } }
                } } }
            }.searchable(text: $query, prompt: "Find a saved thought")
                .task { removed = (try? await model.store?.deletedInboxEntries()) ?? []; projects = (try? await model.store?.projectWorkspaces()) ?? [] }
                .scrollDismissesKeyboard(.interactively).navigationTitle("Assistant inbox")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
