import AssistantCore
import SwiftUI

struct MemoryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var notes: [SavedMemory] = []
    @State private var editing: SavedMemory?
    var body: some View {
        List {
            Section {
                Text("Save preferences and context you want to use again. You choose which notes connected models may receive.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(notes) { note in
                Button { editing = note } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(note.title).font(.headline).foregroundStyle(.primary)
                        Text(note.text).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                        Text((note.conversationID == nil ? "Across conversations" : "One conversation") + " · " + (note.allowsConnectedModels ? "Connected models allowed" : "On-device models only")).font(.caption2).foregroundStyle(.secondary)
                    }.padding(.vertical, 5)
                }
                .swipeActions { Button("Remove", role: .destructive) { Task { try? await model.store?.removeMemory(note.id); await refresh() } } }
            }
            Section {
                Text("Removing a saved note stops adding it to future model context. Existing conversation messages and files remain in your history; removing a note does not erase those originals.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Saved memory")
        .toolbar { Button("Add memory", systemImage: "plus") { editing = SavedMemory(title: "", text: "") } }
        .task { await refresh() }
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
    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $note.title)
                TextEditor(text: $note.text).frame(minHeight: 160).accessibilityLabel("Memory note")
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
                        Task {
                            do { try await model.store?.saveMemory(note); dismiss() }
                            catch { self.error = error.localizedDescription }
                        }
                    }.disabled(note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { acrossConversations = note.conversationID == nil }
        }
    }
}
