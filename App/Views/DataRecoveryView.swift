import AssistantCore
import SwiftUI
import UniformTypeIdentifiers

struct DataRecoveryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var includePrivate = false
    @State private var includeHealth = false
    @State private var busy = false
    @State private var error: String?
    @State private var exportURL: URL?
    @State private var exporting = false
    @State private var importing = false
    @State private var inspected: ArchiveInspection?
    @State private var selectedURL: URL?
    @State private var staged: URL?
    @State private var lastExport: String?
    @State private var pendingSelection: String?
    @State private var libraries: [RestoredLibraryChoice] = []
    var body: some View {
        List {
            Section("On this iPhone") {
                LabeledContent("Conversations", value: model.histories.count.formatted())
                LabeledContent("Original files", value: model.files.count.formatted())
                LabeledContent("Documents", value: model.artifacts.count.formatted())
                LabeledContent("Captures", value: model.captures.count.formatted())
                Text("These records are kept by this app. Connecting a computer does not create an independent backup of the whole phone library.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Export your work") {
                Toggle("Include on-device-only work and drafts", isOn: $includePrivate).disabled(busy)
                Toggle("Include Health-derived work", isOn: $includeHealth).disabled(busy)
                Text("The archive contains readable personal data. Choose where to save it. Account credentials, pairing keys, model weights and pending actions are excluded. Connected-folder originals remain in their own folders.").font(.caption).foregroundStyle(.secondary)
                Button("Create archive", systemImage: "square.and.arrow.up") { Task { await export() } }.disabled(busy || model.isRunning)
                if let lastExport { Text("Last exported: " + lastExport).font(.caption).foregroundStyle(.secondary) }
            }
            Section("Restore an archive") {
                Button("Inspect archive", systemImage: "doc.text.magnifyingglass") { importing = true }.disabled(busy || model.isRunning)
                if let inspected {
                    LabeledContent("Saved", value: inspected.manifest.createdAt.formatted(date: .abbreviated, time: .shortened))
                    Text("\(inspected.manifest.conversations.count) conversations · \(inspected.manifest.artifacts.count) documents · \(inspected.manifest.files.count) files")
                    Text("Excluded: " + inspected.manifest.exclusions.joined(separator: "; ")).font(.caption).foregroundStyle(.secondary)
                    Text("Restore creates a separate library with the original IDs and revisions. It never merges over current work or starts old actions. Sharing permissions require review again.").font(.caption).foregroundStyle(.secondary)
                    if staged == nil { Button("Restore to a separate library") { Task { await restore() } }.disabled(busy || model.isRunning) }
                }
                if let staged {
                    Label("Restored library verified", systemImage: "checkmark.circle")
                    Button(pendingSelection == staged.lastPathComponent ? "Selected for next launch" : "Use restored library on next launch") {
                        do { try PrivatePaths.activateData(staged); pendingSelection = staged.lastPathComponent; error = nil } catch { self.error = error.localizedDescription }
                    }.disabled(model.isRunning || pendingSelection == staged.lastPathComponent)
                    Text("Close and reopen the app when ready. The current library remains available below.").font(.caption).foregroundStyle(.secondary)
                }
                if !libraries.isEmpty {
                    DisclosureGroup("Kept libraries") {
                        ForEach(libraries) { library in
                            Button { do { try PrivatePaths.activateData(library.url); pendingSelection = library.id; error = nil } catch { self.error = error.localizedDescription } } label: {
                                VStack(alignment: .leading, spacing: 4) { Text(library.title); Text(library.detail + (pendingSelection == library.id ? " · selected for next launch" : "")).font(.caption).foregroundStyle(.secondary) }
                            }.disabled(busy || model.isRunning)
                        }
                    }
                }
                Button("Use original library on next launch") {
                    do { try PrivatePaths.activateData(nil); pendingSelection = "data"; error = nil } catch { self.error = error.localizedDescription }
                }.disabled(busy || model.isRunning)
            }
            if busy { ProgressView("Checking and preserving your work") }
            if let error { Section { Text(error).foregroundStyle(.secondary); Button("Dismiss") { self.error = nil } } }
        }.navigationTitle("Data & recovery").navigationBarTitleDisplayMode(.inline)
            .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
                switch result { case .success(let url): Task { await inspect(url) }; case .failure(let error): self.error = error.localizedDescription }
            }
            .sheet(isPresented: $exporting) { if let exportURL { DocumentExportPicker(url: exportURL) { status in
                exporting = false
                if status == "completed" {
                    lastExport = Date().formatted(date: .abbreviated, time: .shortened)
                    do { let root = try PrivatePaths.root(); try Data((lastExport ?? "").utf8).write(to: root.appendingPathComponent("last-archive-export.txt"), options: .atomic) } catch { self.error = error.localizedDescription }
                }
            } } }
            .task {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-product117-recovery"), let store = model.store {
                    do { let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".paarchive"); inspected = try await store.exportPersonalArchive(to: file, includePrivate: true); selectedURL = file } catch { self.error = error.localizedDescription }
                }
                #endif
                if let root = try? PrivatePaths.root() { lastExport = try? String(contentsOf: root.appendingPathComponent("last-archive-export.txt"), encoding: .utf8); libraries = (try? RestoredLibraryChoice.list(root)) ?? []; pendingSelection = (try? String(contentsOf: root.appendingPathComponent("pending-library.txt"), encoding: .utf8)) ?? (try? PrivatePaths.activeData(root: root))?.lastPathComponent } }
    }
    private func export() async {
        guard let store = model.store, !busy, !model.isRunning else { return }
        busy = true; error = nil; defer { busy = false }
        do {
            let target = FileManager.default.temporaryDirectory.appendingPathComponent("PersonalAssistant-\(UUID().uuidString).paarchive")
            _ = try await store.exportPersonalArchive(to: target, includePrivate: includePrivate, includeHealth: includeHealth)
            exportURL = target; exporting = true
        } catch { self.error = error.localizedDescription }
    }
    private func inspect(_ url: URL) async {
        guard !busy else { return }; busy = true; error = nil; defer { busy = false }
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let copied = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".paarchive")
            try await Task.detached { try FileManager.default.copyItem(at: url, to: copied) }.value
            inspected = try await Task.detached { try PersonalArchive.inspect(copied) }.value
            selectedURL = copied; staged = nil
        } catch { self.error = error.localizedDescription }
    }
    private func restore() async {
        guard let selectedURL, !busy, !model.isRunning else { return }; busy = true; error = nil; defer { busy = false }
        do {
            let parent = try PrivatePaths.root().appendingPathComponent("restored-libraries")
            staged = try await Task.detached { try await PersonalArchive.stageRestore(selectedURL, in: parent) }.value
            libraries = try RestoredLibraryChoice.list(parent.deletingLastPathComponent())
        } catch { self.error = error.localizedDescription }
    }
}

private struct RestoredLibraryChoice: Identifiable {
    let id: String
    let url: URL
    let title: String
    let detail: String
    static func list(_ root: URL) throws -> [RestoredLibraryChoice] {
        let parent = root.appendingPathComponent("restored-libraries")
        guard FileManager.default.fileExists(atPath: parent.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: [.creationDateKey]).compactMap { path in
            guard UUID(uuidString: path.lastPathComponent) != nil, path.resolvingSymlinksInPath().deletingLastPathComponent() == parent.resolvingSymlinksInPath(), FileManager.default.fileExists(atPath: path.appendingPathComponent("restore-verified").path) else { return nil }
            let date = (try? path.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let summary = (try? Data(contentsOf: path.appendingPathComponent("restore-summary.json"))).flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
            let count = summary?["conversations"]?.numberValue.flatMap { Int(exactly: $0) }.map { $0.formatted() + " conversations" } ?? "Verified saved library"
            return RestoredLibraryChoice(id: path.lastPathComponent, url: path, title: "Restored " + date.formatted(date: .abbreviated, time: .standard), detail: count)
        }.sorted { $0.title > $1.title }
    }
}
