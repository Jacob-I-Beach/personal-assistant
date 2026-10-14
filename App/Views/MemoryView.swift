import AssistantCore
import SwiftUI

struct MemoryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var notes: [SavedMemory] = []
    @State private var editing: SavedMemory?
    @State private var query = ""
    @State private var failure: String?
    private var matches: [SavedMemory] { notes.filter { query.isEmpty || ($0.title + " " + $0.text).localizedCaseInsensitiveContains(query) } }
    var body: some View {
        List {
            Section {
                Text(model.settings.automaticMemory ? "Useful things you share can become saved context. Review what was learned, correct it, or undo a change." : "Automatic memory is off. You can still add, edit and review saved context.").font(.subheadline).foregroundStyle(.secondary)
                NavigationLink("History and undo") { MemoryHistoryView() }
            }
            if !query.isEmpty && matches.isEmpty { ContentUnavailableView.search(text: query) }
            ForEach(matches) { note in
                Button { editing = note } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(note.title).font(.headline).foregroundStyle(.primary)
                        Text(note.text).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                        Text(note.kind.rawValue.capitalized + " · " + (note.isCurrent() ? note.status.rawValue.capitalized : "Not used in new replies")).font(.caption).foregroundStyle(.secondary)
                        Text((note.conversationID == nil ? "Across conversations" : "One conversation") + " · " + (note.allowsConnectedModels ? "Connected models allowed" : "On-device models only")).font(.caption2).foregroundStyle(.secondary)
                    }.padding(.vertical, 5)
                }
                .swipeActions { Button("Forget", role: .destructive) { Task {
                    do { try await model.store?.removeMemory(note.id); failure = nil; await refresh() }
                    catch { failure = error.localizedDescription }
                } } }
            }
            Section {
                Text("Forgetting a note stops adding it to future model context and can be undone in history. Original chats and files are separate; forgetting a note does not erase them.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Saved memory")
        .safeAreaInset(edge: .bottom) { if let failure { Text(failure).font(.subheadline).padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.bar) } }
        .searchable(text: $query, prompt: "Find a saved fact or preference")
        .toolbar { Button("Add memory", systemImage: "plus") { editing = SavedMemory(title: "", text: "") } }
        .task { await refresh() }
        .onAppear { Task { await refresh() } }
        .sheet(item: $editing, onDismiss: { Task { await refresh() } }) { note in MemoryEditor(note: note) }
    }
    private func refresh() async { notes = (try? await model.store?.memories()) ?? [] }
}
private struct MemoryEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var note: SavedMemory
    @State private var acrossConversations = true
    @State private var error: String?
    @State private var hasExpiration = false
    @State private var expiration = Date().addingTimeInterval(30 * 86400)
    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $note.title)
                TextEditor(text: $note.text).frame(minHeight: 160).accessibilityLabel("Memory note")
                Section {
                DisclosureGroup("Details, source and expiration") {
                    Picker("Kind", selection: $note.kind) { ForEach(MemoryKind.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                    Picker("Profile field", selection: Binding(get: { note.profileKey ?? "" }, set: { note.profileKey = $0.isEmpty ? nil : $0 })) {
                        Text("None").tag(""); Text("Preferred name").tag("preferred_name"); Text("Occupation").tag("occupation"); Text("Interests").tag("interests")
                    }
                    Picker("Status", selection: $note.status) { ForEach(MemoryStatus.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                    TextField("Source or reason", text: $note.source)
                    if let quote = note.sourceQuote { Text(quote).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled) }
                    if let date = note.sourceMessageCreatedAt { LabeledContent("Source date", value: date.formatted(date: .abbreviated, time: .omitted)) }
                    if let confirmed = note.confirmedAt { LabeledContent("You last confirmed", value: confirmed.formatted(date: .abbreviated, time: .omitted)) }
                    Button("Confirm this is current") { note.confirmedAt = Date(); note.status = .active }
                    Toggle("Expires", isOn: $hasExpiration)
                    if hasExpiration { DatePicker("Stop using after", selection: $expiration, displayedComponents: .date) }
                    Text("Superseded and expired notes remain inspectable but are excluded from new replies. Tentative notes are labeled as uncertain.").font(.caption).foregroundStyle(.secondary)
                }
                }
                Toggle("Use across conversations", isOn: $acrossConversations)
                Toggle("Allow with connected models", isOn: $note.allowsConnectedModels)
                Text("Connected models may receive this note when it is selected as relevant context. On-device-only mode continues to block connected inference.").font(.footnote).foregroundStyle(.secondary)
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            }
            .navigationTitle("Memory")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        note.conversationID = acrossConversations ? nil : (note.conversationID ?? model.conversation.id)
                        note.expiresAt = hasExpiration ? expiration : nil
                        Task {
                            do { try await model.store?.saveMemory(note); dismiss() }
                            catch { self.error = error.localizedDescription }
                        }
                    }.disabled(note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { acrossConversations = note.conversationID == nil; hasExpiration = note.expiresAt != nil; expiration = note.expiresAt ?? expiration }
        }
    }
}
