import AssistantCore
import SwiftUI

struct ConnectedFoldersView: View {
    @EnvironmentObject private var model: AppModel
    @State private var choosing = false
    var body: some View {
        List {
            Section {
                ForEach(model.connectedFolders) { folder in
                    NavigationLink { ConnectedFolderView(id: folder.id) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "folder").font(.title2).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(folder.name).fontWeight(.medium)
                                Text(folder.allowsConnectedModels ? "Connected models allowed" : "On-device models only").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.conversation.workspaceIDs.contains(folder.id) { Image(systemName: "checkmark.circle").foregroundStyle(.secondary) }
                        }.padding(.vertical, 5)
                    }
                }
                Button("Connect folder", systemImage: "folder.badge.plus") { choosing = true }.disabled(model.isRunning)
            } footer: { Text("Choose a folder in Files once, then select the chats and models that may use it. You can disconnect it here or revoke access in iPhone Settings.") }
        }
        .navigationTitle("Connected folders").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $choosing) {
            FolderPicker { url in choosing = false; if let url { Task { await model.connectFolder(url) } } }
        }
        .task { await model.refreshWorkspaces() }
    }
}

private struct ConnectedFolderView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let id: UUID
    @State private var disconnecting = false
    @State private var choosing = false
    private var folder: FolderConnection? { model.connectedFolders.first { $0.id == id } }
    var body: some View {
        Group {
            if let folder {
                List {
                    Section {
                        NavigationLink { ConnectedFolderBrowser(workspaceID: id, folderID: nil, title: folder.name) } label: { Label("Browse files", systemImage: "folder") }
                        NavigationLink { FolderEditHistoryView(workspaceID: id) } label: { Label("Edit history", systemImage: "clock.arrow.circlepath") }
                        Button("Reconnect folder", systemImage: "arrow.clockwise") { choosing = true }
                    }
                    Section {
                        Toggle("Use in this chat", isOn: Binding(get: { model.conversation.workspaceIDs.contains(id) }, set: { value in Task { await model.setFolderEnabled(id, enabled: value) } }))
                        Toggle("Allow connected models", isOn: Binding(get: { folder.allowsConnectedModels }, set: { value in Task { await model.updateFolderAccess(folder, connected: value) } }))
                        Toggle("Allow creating and editing files", isOn: Binding(get: { folder.allowsEdits }, set: { value in Task { await model.updateFolderAccess(folder, edits: value) } }))
                    } header: { Text("Assistant access") } footer: {
                        Text("Connected models may receive relevant contents from this folder when it is enabled for a chat. Replacing an existing file always requires a reviewed diff. Files in a cloud provider may sync through that provider.")
                    }.disabled(model.isRunning)
                    Section { Button("Disconnect folder", systemImage: "link", role: .destructive) { disconnecting = true }.disabled(model.isRunning) }
                }
            } else { ContentUnavailableView("Folder disconnected", systemImage: "folder") }
        }
        .navigationTitle(folder?.name ?? "Folder").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $choosing) { FolderPicker { url in choosing = false; if let url { Task { await model.connectFolder(url) } } } }
        .confirmationDialog("Disconnect this folder?", isPresented: $disconnecting, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { Task { await model.disconnectFolder(id); dismiss() } }
        } message: { Text("The app's bookmark and cached edit history will be removed. Files in the selected folder are kept.") }
    }
}

private struct ConnectedFolderBrowser: View {
    @EnvironmentObject private var model: AppModel
    let workspaceID: UUID
    let folderID: UUID?
    let title: String
    @State private var entries: [FolderFile] = []
    @State private var next: Int?
    @State private var error: String?
    @State private var loading = false
    var body: some View {
        List {
            if let error { Section { Text(error).font(.footnote).foregroundStyle(.secondary); Button("Retry") { Task { await load(0) } } } }
            ForEach(entries) { file in
                if file.isDirectory {
                    NavigationLink { ConnectedFolderBrowser(workspaceID: workspaceID, folderID: file.id, title: (file.relativePath as NSString).lastPathComponent) } label: { Label((file.relativePath as NSString).lastPathComponent, systemImage: "folder") }
                } else {
                    NavigationLink { ConnectedFileView(file: file) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label((file.relativePath as NSString).lastPathComponent, systemImage: "doc")
                            Text(ByteCountFormatter.string(fromByteCount: Int64(file.byteCount), countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let next { Button("Load more files") { Task { await load(next) } }.disabled(loading) }
            if loading { ProgressView() }
        }
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .task { await load(0) }
    }
    private func load(_ offset: Int) async {
        guard let service = model.workspaceService else { return }
        loading = true; defer { loading = false }
        do {
            let page = try await service.list(workspaceID, folderID: folderID, offset: offset, remote: false)
            entries = offset == 0 ? page.files : entries + page.files
            next = page.next; error = nil
        } catch { self.error = error.localizedDescription }
    }
}

private struct ConnectedFileView: View {
    @EnvironmentObject private var model: AppModel
    let file: FolderFile
    @State private var text = ""
    @State private var note = "Reading the selected file…"
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(note).font(.caption).foregroundStyle(.secondary)
                Text(String(text.prefix(64_000))).font(.body.monospaced()).textSelection(.enabled)
                if text.count > 64_000 { Text("This preview shows the first 64,000 characters. The assistant can read further sections.").font(.caption).foregroundStyle(.secondary) }
            }.padding().frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle((file.relativePath as NSString).lastPathComponent).navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                guard let value = try await model.workspaceService?.read(file.id, remote: false) else { return }
                let (document, _) = try await DocumentImporter.shared.extract(value.data, filename: (file.relativePath as NSString).lastPathComponent)
                text = document.text; note = document.extractionNote
            } catch { note = error.localizedDescription }
        }
    }
}

private struct FolderEditHistoryView: View {
    @EnvironmentObject private var model: AppModel
    let workspaceID: UUID
    @State private var history: [FileEditProposal] = []
    @State private var selected: FileEditProposal?
    var body: some View {
        List {
            ForEach(history) { edit in
                Button { selected = edit } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(edit.file.relativePath).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                        Text("\(edit.state == "applied" ? "Applied" : edit.state == "cancelled" ? "Cancelled" : "Awaiting review") · \(edit.createdAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }
            }
            if history.isEmpty { Text("Reviewed file changes will appear here, with their original and revised text.").font(.footnote).foregroundStyle(.secondary) }
        }
        .navigationTitle("Edit history").navigationBarTitleDisplayMode(.inline)
        .task { history = await model.workspaceService?.history(workspaceID) ?? [] }
        .sheet(item: $selected) { edit in FileEditReviewView(proposal: edit, readOnly: true) { _ in selected = nil } }
    }
}
