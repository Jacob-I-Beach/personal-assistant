import AssistantCore
import SwiftUI
import MarkdownUI

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel
    var close: () -> Void = {}
    var open: (String) -> Void = { _ in }
    @State private var query = ""
    @State private var matches: [HistoryMatch] = []
    @State private var selectedFolder: UUID?
    @State private var archived = false
    @State private var editingFolder: ChatFolder?
    @State private var deletingFolder: ChatFolder?
    private var visible: [ConversationSummary] {
        model.histories.filter { ($0.archivedAt != nil) == archived && (selectedFolder == nil || $0.folderID == selectedFolder) }
    }
    private var title: String { archived ? "Archived" : model.folders.first { $0.id == selectedFolder }?.name ?? "All chats" }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { model.newConversation(folderID: selectedFolder); close() } label: { rowLabel("New chat", icon: "square.and.pencil").fontWeight(.medium) }.disabled(model.isRunning)
                    Button { close(); open("library") } label: { rowLabel("Library", icon: "square.stack") }
                    Button { close(); open("inbox") } label: { rowLabel("Inbox", icon: "tray") }
                    Button { close(); open("connections") } label: { rowLabel("Connections", icon: "point.3.connected.trianglepath.dotted") }
                    Button { close(); open("activity") } label: { rowLabel("Task activity", icon: "list.bullet.rectangle") }
                }.listRowSeparator(.hidden).listRowBackground(Color.clear)
                if query.isEmpty {
                    Section {
                        Button { selectedFolder = nil; archived = false } label: { selectionRow("All chats", icon: "bubble.left.and.bubble.right", selected: selectedFolder == nil && !archived) }
                        ForEach(model.folders) { folder in
                            HStack {
                                Button { selectedFolder = folder.id; archived = false } label: { selectionRow(folder.name, icon: "folder", selected: selectedFolder == folder.id && !archived) }
                                Menu {
                                    Button("Edit folder", systemImage: "pencil") { editingFolder = folder }
                                    Button("Remove folder", systemImage: "folder.badge.minus", role: .destructive) { deletingFolder = folder }
                                } label: { Image(systemName: "ellipsis").frame(width: 28, height: 32) }.disabled(model.isRunning).accessibilityLabel("Options for \(folder.name)")
                            }
                        }
                        Button { editingFolder = ChatFolder(name: "") } label: { rowLabel("New folder", icon: "folder.badge.plus").foregroundStyle(.secondary) }.disabled(model.isRunning)
                    } header: { Text("Folders") }.listRowSeparator(.hidden).listRowBackground(Color.clear)
                    Section(title) {
                        if visible.isEmpty { Text(archived ? "Archived chats will appear here." : "Your conversations will appear here.").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 12).listRowSeparator(.hidden) }
                        ForEach(visible) { chat in
                            HStack(alignment: .center, spacing: 6) {
                                Button { Task { await model.selectConversation(chat); close() } } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(chat.title).lineLimit(2).font(.subheadline.weight(chat.id == model.conversation.id ? .semibold : .regular))
                                        Text(chat.updatedAt, format: .dateTime.month(.abbreviated).day()).font(.caption2).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6).contentShape(Rectangle())
                                }.disabled(model.isRunning)
                                ChatActionsMenu(chat: chat)
                            }.listRowSeparator(.hidden)
                                .listRowBackground(chat.id == model.conversation.id ? Color.primary.opacity(0.055) : Color.clear)
                        }
                    }
                } else {
                    Section("Matching conversations") {
                        ForEach(matches) { match in
                            Button {
                                if let summary = model.histories.first(where: { $0.id == match.conversationID }) { Task { await model.selectConversation(summary); close() } }
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(match.title).font(.subheadline.weight(.medium)).lineLimit(2)
                                    Text(MarkdownContent(match.excerpt).renderPlainText()).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                                }.padding(.vertical, 5).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.disabled(model.isRunning)
                        }
                        if matches.isEmpty { Text("No matching chats").foregroundStyle(.secondary) }
                    }.listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
                Section {
                    Button { selectedFolder = nil; archived.toggle(); query = "" } label: { rowLabel(archived ? "Back to chats" : "Archived chats", icon: archived ? "bubble.left.and.bubble.right" : "archivebox") }
                    Button { close(); open("settings") } label: { rowLabel("Settings & access", icon: "gearshape") }
                    Button { close(); open("watch") } label: { rowLabel("Watch requests", icon: "applewatch") }
                }.listRowSeparator(.hidden).listRowBackground(Color.clear)
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
            .buttonStyle(.plain)
            .background(Color(uiColor: .secondarySystemBackground))
            .navigationTitle("Personal Assistant").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close sidebar", systemImage: "sidebar.left") { close() }.labelStyle(.iconOnly) } }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search chats")
            .task(id: query) {
                guard !query.isEmpty else { matches = []; return }
                try? await Task.sleep(for: .milliseconds(200)); guard !Task.isCancelled else { return }
                let result = await model.searchHistory(query)
                if !Task.isCancelled { matches = result }
            }
            .sheet(item: $editingFolder) { FolderEditor(folder: $0) }
            .alert("Remove folder?", isPresented: Binding(get: { deletingFolder != nil }, set: { if !$0 { deletingFolder = nil } })) {
                Button("Remove folder", role: .destructive) {
                    if let id = deletingFolder?.id { Task { await model.removeFolder(id); if selectedFolder == id { selectedFolder = nil } } }
                    deletingFolder = nil
                }
                Button("Cancel", role: .cancel) { deletingFolder = nil }
            } message: { Text("Its chats will remain in All chats. The folder's instructions will be removed.") }
        }
    }
    private func selectionRow(_ text: String, icon: String, selected: Bool) -> some View {
        HStack { Label(text, systemImage: icon).lineLimit(1); Spacer(); if selected { Image(systemName: "checkmark").font(.caption.weight(.semibold)) } }
            .font(.subheadline).contentShape(Rectangle())
    }
    private func rowLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon).frame(maxWidth: .infinity, minHeight: 38, alignment: .leading).contentShape(Rectangle())
    }
}

struct ChatActionsMenu: View {
    @EnvironmentObject private var model: AppModel
    let chat: ConversationSummary
    @State private var renaming = false
    @State private var name = ""
    @State private var moving = false
    @State private var deleting = false
    var body: some View {
        Menu {
            Button("Rename", systemImage: "pencil") { name = chat.title; renaming = true }
            Button("Move to folder", systemImage: "folder") { moving = true }
            Button(chat.archivedAt == nil ? "Archive" : "Restore", systemImage: chat.archivedAt == nil ? "archivebox" : "tray.and.arrow.up") { Task { await model.changeChat(chat.id, .archive(chat.archivedAt == nil)) } }
            Button("Delete", systemImage: "trash", role: .destructive) { deleting = true }
        } label: { Image(systemName: "ellipsis").frame(width: 36, height: 44).contentShape(Rectangle()).foregroundStyle(.secondary) }
            .accessibilityLabel("Options for \(chat.title)").disabled(model.isRunning)
            .alert("Rename chat", isPresented: $renaming) {
                TextField("Chat title", text: $name)
                Button("Save") { Task { await model.changeChat(chat.id, .rename(name)) } }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Move chat", isPresented: $moving, titleVisibility: .visible) {
                Button("No folder") { Task { await model.changeChat(chat.id, .move(nil)) } }
                ForEach(model.folders) { folder in Button(folder.name) { Task { await model.changeChat(chat.id, .move(folder.id)) } } }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Delete this chat?", isPresented: $deleting) {
                Button("Delete chat", role: .destructive) { Task { await model.changeChat(chat.id, .delete) } }
                Button("Cancel", role: .cancel) {}
            } message: { Text("This removes its messages, generated files and chat-only memories. Imported Library files and captures remain. Archive it instead if you may need it later.") }
    }
}

private struct FolderEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var folder: ChatFolder
    @State private var saving = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Topic") { TextField("Folder name", text: $folder.name) }
                Section {
                    TextEditor(text: $folder.instructions).frame(minHeight: 140).accessibilityLabel("Folder instructions")
                } header: { Text("Instructions, optional") } footer: { Text("Context you want the assistant to use in chats inside this folder. These instructions are shared with the model you choose.") }
            }.navigationTitle("Folder").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { saving = true; Task { if await model.saveFolder(folder) { dismiss() }; saving = false } }.disabled(saving || folder.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
        }
    }
}
