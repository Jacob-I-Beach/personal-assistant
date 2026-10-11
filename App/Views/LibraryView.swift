import AssistantCore
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var showImport = false
    private var latestArtifacts: [ArtifactRecord] {
        let oldVersions = Set(model.artifacts.compactMap(\.previousRevisionID))
        return model.artifacts.filter { !oldVersions.contains($0.id) }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { ProjectsView() } label: { Label("Projects", systemImage: "square.stack.3d.up") }
                    NavigationLink { ConnectedFoldersView() } label: { Label("Connected folders", systemImage: "folder") }
                    NavigationLink { OutputsView() } label: { Label("Outputs in Files", systemImage: "externaldrive") }
                    NavigationLink { CaptureLibraryView() } label: { Label("Captures · \(model.captures.count)", systemImage: "viewfinder") }
                    NavigationLink { MemoryView() } label: { Label("Saved memory", systemImage: "brain.head.profile") }
                }
                Section("Your files") {
                    ForEach(model.files.filter { query.isEmpty || ($0.filename + " " + $0.text).localizedCaseInsensitiveContains(query) }) { file in
                        NavigationLink { WorkspaceFileView(id: file.id) } label: { WorkspaceFileRow(file: file) }
                    }
                    if latestArtifacts.isEmpty && model.files.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Useful work, kept here").font(.headline)
                            Text("Documents, tables, scripts, and other files created in a conversation will appear here. You can edit, share, and revisit them.").foregroundStyle(.secondary)
                        }.padding(.vertical, 10)
                    }
                    ForEach(latestArtifacts.filter { query.isEmpty || ($0.filename + " " + $0.content).localizedCaseInsensitiveContains(query) }) { artifact in
                        NavigationLink { ArtifactDetailView(artifact: artifact) } label: { ArtifactCard(artifact: artifact) }
                    }
                }
            }
            .navigationTitle("Library")
            .searchable(text: $query, prompt: "Search files and contents")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Import files", systemImage: "doc.badge.plus") { showImport = true }.disabled(model.isImportingFiles) }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .refreshable { await model.refresh() }
            .fileImporter(isPresented: $showImport, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): model.importFiles(urls, attach: false)
                case .failure(let error): model.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
struct ArtifactCard: View {
    let artifact: ArtifactRecord
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: artifact.filename.hasSuffix(".csv") ? "tablecells" : "doc.text").font(.title2).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(artifact.filename).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                Text("\(ByteCountFormatter.string(fromByteCount: Int64(artifact.content.utf8.count), countStyle: .file)) · \(artifact.createdAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 8)
    }
}
struct ArtifactDetailView: View {
    @EnvironmentObject private var model: AppModel
    @State private var artifact: ArtifactRecord
    @State private var text = ""
    @State private var editing = false
    @State private var exportURL: URL?
    @State private var saving = false
    @State private var showExport = false
    @State private var exportNotice: String?
    @State private var draftTask: Task<Void, Never>?
    @State private var history: [ArtifactRecord] = []
    @State private var showHistory = false
    init(artifact: ArtifactRecord) { _artifact = State(initialValue: artifact) }
    var body: some View {
        Group {
            if editing { TextEditor(text: $text).font(.body.monospaced()).padding(10).accessibilityLabel("Edit artifact").disabled(saving) }
            else {
                ScrollView {
                    if artifact.filename.hasSuffix(".md") { AssistantMarkdown(text: text).padding(20).frame(maxWidth: .infinity, alignment: .leading) }
                    else { Text(text).font(.body.monospaced()).textSelection(.enabled).padding(20).frame(maxWidth: .infinity, alignment: .leading) }
                }
            }
        }
        .navigationTitle(artifact.filename).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if editing {
                    Button("Save revision") {
                        saving = true; draftTask?.cancel()
                        Task {
                            if let revised = await model.reviseArtifact(artifact, content: text) {
                                artifact = revised; text = revised.content; exportURL = await model.artifactURL(revised); editing = false
                            }
                            saving = false
                        }
                    }.disabled(saving || text == artifact.content)
                } else {
                    Button("Edit", systemImage: "pencil") { editing = true }
                    Button("Revision history", systemImage: "clock.arrow.circlepath") {
                        Task { history = (try? await model.store?.artifactHistory(artifact.id)) ?? []; showHistory = true }
                    }
                    if let exportURL {
                        Menu {
                            ShareLink(item: exportURL) { Label("Share", systemImage: "square.and.arrow.up") }
                            Button("Save to Files", systemImage: "folder.badge.plus") { exportNotice = nil; showExport = true }
                        } label: { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Artifact actions")
                    }
                }
            }
        }
        .sheet(isPresented: $showExport, onDismiss: { if exportNotice == nil { exportNotice = "Export cancelled." } }) {
            if let exportURL {
                DocumentExportPicker(url: exportURL) { status in
                    exportNotice = status == "completed" ? "Export completed. Cloud synchronization was not checked." : "Export cancelled."
                    showExport = false
                }
            }
        }
        .sheet(isPresented: $showHistory) {
            NavigationStack {
                List {
                    Text("Current revision \(artifact.revision)").font(.headline)
                    if history.isEmpty { Text("Earlier revisions will appear here after a saved change.").foregroundStyle(.secondary) }
                    ForEach(history, id: \.revision) { earlier in
                        DisclosureGroup("Revision \(earlier.revision)") {
                            Text(earlier.content).font(.subheadline).textSelection(.enabled)
                            Button("Restore as a new revision") {
                                Task { if let revised = await model.reviseArtifact(artifact, content: earlier.content) { artifact = revised; text = revised.content; exportURL = await model.artifactURL(revised); showHistory = false } }
                            }
                        }
                    }
                }.navigationTitle("Document history").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showHistory = false } } }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let exportNotice { Text(exportNotice).font(.caption).foregroundStyle(.secondary).padding().frame(maxWidth: .infinity).background(.bar) }
        }
        .task {
            if let draft = try? await model.store?.artifactDraft(id: artifact.id) { text = draft; editing = true }
            else { text = artifact.content }
            exportURL = await model.artifactURL(artifact)
        }
        .onChange(of: text) { _, value in
            guard editing, !saving else { return }
            draftTask?.cancel()
            let id = artifact.id
            draftTask = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                do { try await model.store?.saveArtifactDraft(id: id, text: value) }
                catch { model.errorMessage = error.localizedDescription }
            }
        }
        .onDisappear {
            draftTask?.cancel()
            if editing && text != artifact.content {
                let id = artifact.id, value = text
                Task { try? await model.store?.saveArtifactDraft(id: id, text: value) }
            }
        }
    }
}
