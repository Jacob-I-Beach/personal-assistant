import AssistantCore
import QuickLook
import SwiftUI

struct WorkspaceFileRow: View {
    let file: WorkspaceFile
    var body: some View { OutputRow(value: OutputPresentation(file), symbol: file.icon) }
}

struct WorkspaceFileView: View {
    @Environment(\.conversationDisplay) private var display
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var navigation: ChatNavigation
    @Environment(\.dismiss) private var dismiss
    let id: UUID
    var previewOnly = false
    @State private var record: WorkspaceFile?
    @State private var url: URL?
    @State private var failure: String?
    @State private var showInfo = false
    @State private var deleting = false
    private var file: WorkspaceFile? { record ?? model.files.first { $0.id == id } }
    var body: some View {
        Group {
            if let file, let url { FileContentPreview(file: file, url: url) }
            else if let failure { ContentUnavailableView("Original unavailable", systemImage: "doc", description: Text(failure)) }
            else { ProgressView("Opening original file") }
        }
        .navigationTitle(file?.filename ?? "File").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let url { ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Share original") }
                Button("File info", systemImage: "info.circle") { showInfo = true }.disabled(file == nil)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !previewOnly, display?.readOnly != true, let file {
                VStack(alignment: .leading, spacing: 8) {
                    Button("Ask about this file", systemImage: "text.bubble") {
                        let ref = ContextReference(kind: .file, sourceID: id.uuidString, title: file.filename, conversationID: model.conversation.id, health: file.containsHealthData)
                        navigation.compose(ContextualDraftProposal(reference: ref, prompt: "Help me understand this file."), afterDismissal: model.rootPresentation != nil)
                    }.buttonStyle(.bordered).disabled(model.isRunning || (file.containsHealthData && file.conversationID != model.conversation.id))
                    if file.containsHealthData && file.conversationID != model.conversation.id { Text("Use the original conversation to discuss this Health-derived file.").font(.caption).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(.bar)
            }
        }
        .sheet(isPresented: $showInfo) {
            NavigationStack {
                List {
                    if let file {
                        Section { WorkspaceFileRow(file: file); if let url { ExportDocumentButton(url: url) } }
                        Section("What the assistant can read") {
                            Text(file.extractionNote.isEmpty ? "Original file retained. Extracted text may not preserve every detail." : file.extractionNote).font(.subheadline).foregroundStyle(.secondary)
                            if !file.text.isEmpty { DisclosureGroup("Extracted text · \(file.text.count) characters") { Text(String(file.text.prefix(24_000))).font(.caption.monospaced()).textSelection(.enabled) } }
                        }
                        if !previewOnly && display?.readOnly != true {
                            Section {
                                Toggle("Include in workspace search", isOn: Binding(get: { file.allowsWorkspaceSearch }, set: { value in Task { await model.shareFile(id, workspace: value, connected: file.allowsConnectedModels); await load() } }))
                                Toggle("Allow connected models to find it", isOn: Binding(get: { file.allowsConnectedModels }, set: { value in Task { await model.shareFile(id, workspace: file.allowsWorkspaceSearch, connected: value); await load() } }))
                            } header: { Text("Access outside attached chats") } footer: {
                                Text("By default, models only see this file when you attach it. Workspace search also needs to be enabled in Settings. Health-derived files stay in their original conversation.")
                            }.disabled(model.isRunning || file.containsHealthData)
                            Section { Button("Delete file", systemImage: "trash", role: .destructive) { deleting = true }.disabled(model.isRunning) }
                        }
                        if let failure { Text(failure).foregroundStyle(.secondary) }
                    }
                }.navigationTitle("File info").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showInfo = false } } }
                    .alert("Delete this Library file?", isPresented: $deleting) {
                        Button("Delete file", role: .destructive) { Task { await model.removeFile(id); if !model.files.contains(where: { $0.id == id }) { showInfo = false; dismiss() } } }
                        Button("Cancel", role: .cancel) { }
                    } message: { Text("The app's stored original and extracted text will be removed. Previous chat text and exported copies remain.") }
            }
        }
        .task(id: id) { await load() }
        .onChange(of: model.files.first(where: { $0.id == id })) { _, value in if let value { record = value } }
    }
    private func load() async {
        do {
            guard let store = model.store else { return }
            record = try await store.workspaceFile(id); url = try await store.workspaceFileURL(id); failure = nil
        } catch { failure = error.localizedDescription }
    }
}

struct FileAttachmentPicker: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let conversationID: UUID
    @State private var query = ""
    @State private var selected: [UUID] = []
    @State private var preview: ChatDestination?
    @State private var adding = false
    @State private var failure: String?
    private var visible: [WorkspaceFile] { model.files.filter { query.isEmpty || $0.filename.localizedCaseInsensitiveContains(query) } }
    var body: some View {
        NavigationStack {
            List {
                ForEach(visible) { file in
                    let already = model.attachedFileIDs.contains(file.id)
                    let blocked = file.containsHealthData && file.conversationID != conversationID
                    HStack(spacing: 8) {
                        Button {
                            if selected.contains(file.id) { selected.removeAll { $0 == file.id } } else { selected.append(file.id) }
                        } label: {
                            HStack { Image(systemName: already || selected.contains(file.id) ? "checkmark.circle.fill" : "circle"); VStack(alignment: .leading) { WorkspaceFileRow(file: file); if blocked { Text("Available in its original conversation").font(.caption).foregroundStyle(.secondary) } else if already { Text("Already attached").font(.caption).foregroundStyle(.secondary) } } }
                        }.disabled(model.isRunning || already || blocked || adding).buttonStyle(.plain)
                            .accessibilityLabel("Select \(file.filename)").accessibilityValue(already || selected.contains(file.id) ? "Selected" : "Not selected")
                        Button { preview = .file(file.id) } label: { Image(systemName: "eye").frame(width: 44, height: 44) }.buttonStyle(.borderless).accessibilityLabel("Preview \(file.filename)")
                    }
                }
                if visible.isEmpty { ContentUnavailableView(model.files.isEmpty ? "No files yet" : "No matching files", systemImage: "doc", description: Text(model.files.isEmpty ? "Use Choose files to add a document to Library." : "Try a different filename.")) }
                if let failure { Text(failure).foregroundStyle(.secondary) }
            }
            .searchable(text: $query, prompt: "Find a file")
            .navigationTitle("Attach from Library").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Add \(selected.count)") {
                    adding = true
                    Task { defer { adding = false }; do { try await model.attachSelectedFiles(selected, to: conversationID); dismiss() } catch { failure = error.localizedDescription } }
                }.disabled(selected.isEmpty || adding || model.isRunning) }
            }
            .sheet(item: $preview) { item in
                if case .file(let id) = item { NavigationStack { WorkspaceFileView(id: id, previewOnly: true).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { preview = nil } } } } }
            }
        }
    }
}
