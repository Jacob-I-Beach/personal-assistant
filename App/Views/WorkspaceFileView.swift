import AssistantCore
import QuickLook
import SwiftUI

struct WorkspaceFileRow: View {
    let file: WorkspaceFile
    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: file.icon).font(.title2).foregroundStyle(.secondary).frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(file.filename).font(.subheadline.weight(.medium)).lineLimit(2).foregroundStyle(.primary)
                Text("\(ByteCountFormatter.string(fromByteCount: Int64(file.byteCount), countStyle: .file)) · \(file.createdAt.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 7)
    }
}

struct WorkspaceFileView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var navigation: ChatNavigation
    let id: UUID
    @State private var preview: URL?
    @State private var url: URL?
    @State private var deleting = false
    @Environment(\.dismiss) private var dismiss
    private var file: WorkspaceFile? { model.files.first { $0.id == id } }
    var body: some View {
        Group {
            if let file {
                List {
                    Section {
                        WorkspaceFileRow(file: file)
                        if let url {
                            if ["html", "htm", "svg"].contains(url.pathExtension.lowercased()) {
                                NavigationLink("Preview source text") { ScrollView { Text(String(file.text.prefix(100_000))).font(.caption.monospaced()).textSelection(.enabled).padding() }.navigationTitle(file.filename) }
                            } else { Button("Preview original", systemImage: "doc.viewfinder") { preview = url } }
                            ShareLink(item: url) { Label("Share original", systemImage: "square.and.arrow.up") }
                            ExportDocumentButton(url: url)
                        }
                        Button("Attach to current chat", systemImage: "paperclip") {
                            model.attachFile(id); AppFeedback.play(.selection)
                            if navigation.showLibrary { navigation.showLibrary = false }
                            else { dismiss() }
                        }.disabled(model.isRunning || (file.containsHealthData && file.conversationID != model.conversation.id))
                    }
                    Section("What the assistant can read") {
                        Text(file.extractionNote).font(.footnote).foregroundStyle(.secondary)
                        if !file.text.isEmpty {
                            DisclosureGroup("Extracted text · \(file.text.count) characters") {
                                Text(String(file.text.prefix(24_000))).font(.caption.monospaced()).textSelection(.enabled)
                                if file.text.count > 24_000 { Text("Preview shortened. The assistant can read the remaining extracted text in sections.").font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                        Text("For supported ChatGPT models, recently attached originals can also be sent as file inputs. Connected file processing may differ from this on-device extraction.").font(.caption).foregroundStyle(.secondary)
                    }
                    Section {
                        Toggle("Include in workspace search", isOn: Binding(get: { file.allowsWorkspaceSearch }, set: { value in Task { await model.shareFile(id, workspace: value, connected: file.allowsConnectedModels) } }))
                        Toggle("Allow connected models to find it", isOn: Binding(get: { file.allowsConnectedModels }, set: { value in Task { await model.shareFile(id, workspace: file.allowsWorkspaceSearch, connected: value) } }))
                    } header: { Text("Access outside attached chats") } footer: {
                        Text("By default, models only see a file when you attach it. Workspace search must also be enabled in Settings. Health-derived files remain in their original conversation.")
                    }.disabled(model.isRunning || file.containsHealthData)
                    Section { Button("Delete file", systemImage: "trash", role: .destructive) { deleting = true }.disabled(model.isRunning) }
                }
            } else { ContentUnavailableView("File removed", systemImage: "doc") }
        }
        .navigationTitle(file?.filename ?? "File").navigationBarTitleDisplayMode(.inline)
        .task(id: id) { url = await model.fileURL(id) }
        .quickLookPreview($preview)
        .alert("Delete this Library file?", isPresented: $deleting) {
            Button("Delete file", role: .destructive) { Task { await model.removeFile(id); dismiss() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The original stored inside this app and its extracted text will be removed. Previous chat text and any copies you exported remain.") }
    }
}

struct FileAttachmentPicker: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    var body: some View {
        NavigationStack {
            List {
                ForEach(model.files.filter { query.isEmpty || $0.filename.localizedCaseInsensitiveContains(query) }) { file in
                    Button { model.attachFile(file.id); dismiss() } label: { WorkspaceFileRow(file: file) }
                        .disabled(model.isRunning || (file.containsHealthData && file.conversationID != model.conversation.id))
                }
            }.overlay { if model.files.isEmpty { ContentUnavailableView("No files yet", systemImage: "doc", description: Text("Use Choose files to add a document to your Library.")) } }
                .searchable(text: $query, prompt: "Find a file")
                .navigationTitle("Attach from Library").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
