import AssistantCore
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var showImport = false
    @State private var searchResult: LibrarySearchResult?
    @State private var searching = false
    @State private var searchError: String?
    @State private var scope = "All"
    @State private var filename = ""
    @State private var fileType = ""
    @State private var recentOnly = false
    @State private var currentChatOnly = false
    private var hasFilter: Bool { !query.isEmpty || !filename.isEmpty || !fileType.isEmpty || recentOnly || currentChatOnly }
    private var searchKey: String { query + filename + fileType + String(recentOnly) + String(currentChatOnly) + model.files.map { $0.id.uuidString }.joined() + model.artifacts.map { $0.id.uuidString + String($0.revision) }.joined() }
    private var filteredFiles: [WorkspaceFile] { scope == "Documents" ? [] : model.files.filter { !hasFilter || searchResult?.fileIDs.contains($0.id) == true } }
    private var filteredArtifacts: [ArtifactRecord] { scope == "Imported files" ? [] : latestArtifacts.filter { !hasFilter || searchResult?.artifactIDs.contains($0.id) == true } }
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
                    Picker("Show", selection: $scope) { ForEach(["All", "Imported files", "Documents"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented)
                    DisclosureGroup("Filter files") {
                        TextField("Filename contains", text: $filename)
                        Picker("File type", selection: $fileType) { Text("Any type").tag(""); ForEach(["pdf", "md", "csv", "txt", "png", "jpg", "xlsx", "docx"], id: \.self) { Text($0.uppercased()).tag($0) } }
                        Toggle("Added in the last 30 days", isOn: $recentOnly)
                        Toggle("From current chat", isOn: $currentChatOnly)
                        if hasFilter { Button("Clear search and filters") { query = ""; filename = ""; fileType = ""; recentOnly = false; currentChatOnly = false } }
                    }
                    if searching { ProgressView("Searching Library") }
                    if let searchError { Text(searchError).foregroundStyle(.secondary) }
                    if hasFilter && !searching && searchError == nil && filteredFiles.isEmpty && filteredArtifacts.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                    ForEach(filteredFiles) { file in
                        NavigationLink { WorkspaceFileView(id: file.id) } label: { VStack(alignment: .leading) { WorkspaceFileRow(file: file); if let excerpt = searchResult?.excerpts[file.id], !query.isEmpty { Text(excerpt).font(.caption).foregroundStyle(.secondary).lineLimit(3) } } }
                    }
                    if latestArtifacts.isEmpty && model.files.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Useful work, kept here").font(.headline)
                            Text("Documents, tables, scripts, and other files created in a conversation will appear here. You can edit, share, and revisit them.").foregroundStyle(.secondary)
                        }.padding(.vertical, 10)
                    }
                    ForEach(filteredArtifacts) { artifact in
                        NavigationLink { ArtifactDetailView(artifact: artifact) } label: { VStack(alignment: .leading) { ArtifactCard(artifact: artifact); if let excerpt = searchResult?.excerpts[artifact.id], !query.isEmpty { Text(excerpt).font(.caption).foregroundStyle(.secondary).lineLimit(3) } } }
                    }
                }
            }
            .navigationTitle("Library")
            .searchable(text: $query, prompt: "Search files and contents")
            .task(id: searchKey) {
                guard hasFilter else { searchResult = nil; searching = false; searchError = nil; return }
                searching = true; searchError = nil; searchResult = nil
                do {
                    try await Task.sleep(for: .milliseconds(200))
                    var filter = LibrarySearchFilter(); filter.filename = filename; filter.fileExtension = fileType; filter.since = recentOnly ? Date().addingTimeInterval(-30 * 86400) : nil; filter.conversationID = currentChatOnly ? model.conversation.id : nil
                    let result = try await model.store?.searchLibrary(query, filter: filter)
                    try Task.checkCancellation(); searchResult = result; searching = false
                } catch is CancellationError { }
                catch { searchError = error.localizedDescription; searching = false }
            }
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
    @EnvironmentObject private var model: AppModel
    let artifact: ArtifactRecord
    var body: some View { OutputRow(value: OutputPresentation(model.artifacts.first(where: { $0.id == artifact.id }) ?? artifact, conversation: model.conversation.id == artifact.conversationID ? model.conversation : nil), symbol: artifact.filename.hasSuffix(".csv") ? "tablecells" : "doc.text") }
}
struct ArtifactDetailView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var navigation: ChatNavigation
    @StateObject private var editor: ArtifactEditor
    @State private var exportURL: URL?
    @State private var showExport = false
    @State private var showHistory = false
    @State private var showComparison = false
    @State private var discardDraft = false
    @State private var history: [ArtifactRecord] = []
    init(artifact: ArtifactRecord) { _editor = StateObject(wrappedValue: ArtifactEditor(artifact: artifact)) }
    var body: some View {
        VStack(spacing: 0) {
            if editor.loading { ProgressView("Opening saved document").frame(maxWidth: .infinity, maxHeight: .infinity) }
            else {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(editor.editing ? (editor.draftSaved ? "Draft saved on this device" : "Editing draft") : "Saved revision \(editor.artifact.revision)").font(.subheadline.weight(.medium)).accessibilityIdentifier("artifact-version-status")
                        if editor.editing { Text(editor.baseRevision.map { "Based on revision \($0)" } ?? "Older draft · compare before saving").font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    if !editor.editing && editor.hasDraft { Button("Resume draft") { editor.beginEditing() }.font(.subheadline) }
                }.padding(.horizontal, 20).padding(.vertical, 12)
                if editor.editing {
                    TextEditor(text: $editor.text).font(.body.monospaced()).padding(10).accessibilityLabel("Edit artifact").disabled(editor.saving)
                } else {
                    ScrollView {
                        if editor.artifact.filename.hasSuffix(".md") { AssistantMarkdown(text: editor.artifact.content).padding(20).frame(maxWidth: .infinity, alignment: .leading) }
                        else if ["csv", "tsv"].contains(URL(fileURLWithPath: editor.artifact.filename).pathExtension.lowercased()) {
                            DelimitedContentView(text: editor.artifact.content, delimiter: editor.artifact.filename.lowercased().hasSuffix(".tsv") ? "\t" : ",")
                        } else { Text(editor.artifact.content).font(.body.monospaced()).textSelection(.enabled).padding(20).frame(maxWidth: .infinity, alignment: .leading) }
                    }
                }
            }
        }
        .navigationTitle(editor.artifact.filename).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if editor.editing {
                    Menu {
                        Button("View saved revision") { Task { await editor.showSaved(); await refreshExport() } }
                        Button("Compare with saved revision") { Task { await editor.reviewCurrent(); showComparison = true } }
                        Button("Discard draft", role: .destructive) { discardDraft = true }
                    } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Draft actions")
                    Button("Save revision") { Task { await save() } }.disabled(!editor.canSave)
                } else {
                    Button("Ask about this", systemImage: "text.bubble") {
                        let document = editor.artifact
                        Task {
                            guard !model.isRunning else { return }
                            if model.conversation.id != document.conversationID, let chat = model.histories.first(where: { $0.id == document.conversationID }) { await model.selectConversation(chat) }
                            let ref = ContextReference(kind: .artifact, sourceID: document.id.uuidString, title: document.filename, conversationID: document.conversationID, revision: document.revision, localOnly: document.containsLocalOnlyContext, health: document.containsHealthData)
                            navigation.compose(ContextualDraftProposal(reference: ref, prompt: "Help me with this document."), afterDismissal: model.rootPresentation != nil)
                        }
                    }.disabled(model.isRunning || editor.loading)
                    Button("Edit", systemImage: "pencil") { editor.beginEditing() }.disabled(editor.loading)
                    Menu {
                        Button("Revision history", systemImage: "clock.arrow.circlepath") {
                            Task { history = (try? await model.store?.artifactHistory(editor.artifact.id)) ?? []; showHistory = true }
                        }
                        if let exportURL {
                            ShareLink(item: exportURL) { Label("Share saved revision", systemImage: "square.and.arrow.up") }
                            Button("Save to Files", systemImage: "folder.badge.plus") { showExport = true }
                        }
                    } label: { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Artifact actions")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                if editor.needsComparison {
                    Text("The draft is based on a different saved version. Compare before saving.").font(.subheadline)
                    Button("Compare versions") { Task { await editor.reviewCurrent(); showComparison = true } }
                }
                if let error = editor.error { Text(error).font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("artifact-local-error") }
                if let notice = editor.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(editor.needsComparison || editor.error != nil || editor.notice != nil ? 16 : 0).background(.bar)
        }
        .confirmationDialog("Discard this draft?", isPresented: $discardDraft, titleVisibility: .visible) {
            Button("Discard draft", role: .destructive) { Task { await editor.discard(); await refreshExport() } }
            Button("Keep draft", role: .cancel) { }
        } message: { Text("The saved document and its revision history will stay unchanged.") }
        .sheet(isPresented: $showComparison) {
            NavigationStack {
                List {
                    Section("Saved revision \(editor.artifact.revision)") { Text(editor.artifact.content).textSelection(.enabled) }
                    Section(editor.baseRevision.map { "Draft based on revision \($0)" } ?? "Draft with an unknown base") { Text(editor.text).textSelection(.enabled) }
                    Section {
                        Button("Use draft with this saved revision") { Task { await editor.useDraftOverCurrentRevision(); showComparison = false } }
                        Text("This keeps your draft and updates its base. Save revision is still a separate action.").font(.caption).foregroundStyle(.secondary)
                    }
                }.navigationTitle("Compare versions").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showComparison = false } } }
            }
        }
        .sheet(isPresented: $showHistory) {
            NavigationStack {
                List {
                    Text("Current revision \(editor.artifact.revision)").font(.headline)
                    if history.isEmpty { Text("Earlier revisions appear after a saved change.").foregroundStyle(.secondary) }
                    ForEach(history, id: \.revision) { earlier in
                        DisclosureGroup("Revision \(earlier.revision)") {
                            Text(earlier.content).textSelection(.enabled)
                            Button("Use this version as a draft") { editor.useHistoricalText(earlier.content); showHistory = false }.disabled(editor.hasDraft)
                            if editor.hasDraft { Text("Finish or discard your existing draft first.").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }.navigationTitle("Document history").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showHistory = false } } }
            }
        }
        .sheet(isPresented: $showExport) {
            if let exportURL { DocumentExportPicker(url: exportURL) { result in editor.notice = result == "completed" ? "Export completed. Cloud synchronization was not checked." : "Export cancelled."; showExport = false } }
        }
        .task { await editor.load(model.store); await refreshExport() }
        .onChange(of: editor.text) { _, _ in editor.changed() }
        .onChange(of: model.artifacts.first(where: { $0.id == editor.artifact.id })?.revision) { _, _ in
            guard !editor.loading, !editor.saving else { return }
            Task { await editor.reviewCurrent(); if !editor.editing { await refreshExport() } }
        }
        .onDisappear { Task { await editor.flush() } }
    }
    private func refreshExport() async {
        do { exportURL = try await model.store?.exportArtifact(editor.artifact) }
        catch { editor.error = error.localizedDescription }
    }
    private func save() async {
        if let result = await editor.save() {
            if let warning = await model.publishArtifactEdit(previous: result.previous, saved: result.saved) { editor.notice = warning }
            await refreshExport(); AppFeedback.play(.saved)
        }
    }
}
