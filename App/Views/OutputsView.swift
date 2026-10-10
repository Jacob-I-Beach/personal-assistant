import AssistantCore
import QuickLook
import SwiftUI

struct OutputsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var outputs: [OutputRecord] = []
    @State private var error: String?
    var body: some View {
        List {
            Section {
                Label("On My iPhone → Personal Assistant → Outputs", systemImage: "folder")
                    .font(.subheadline)
                Text("New files created by the assistant get a copy here automatically. Private chats, credentials, and bookmarks stay outside this folder. Editing a Files copy does not change the original kept in Library.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Created files") {
                ForEach(outputs) { output in
                    NavigationLink { OutputDetailView(output: output) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(output.filename, systemImage: "doc")
                            Text(output.status == "saved_local" ? "Saved on this iPhone" : "Save needs attention")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }
                }
                if outputs.isEmpty { Text(error ?? "Files created in new conversations will appear here. Existing Library items can be saved with Save to Files.").font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Outputs in Files").navigationBarTitleDisplayMode(.inline)
        .task { await load() }.refreshable { await load() }
    }
    private func load() async {
        do { outputs = try await model.store?.outputRecords() ?? [] }
        catch { self.error = error.localizedDescription }
    }
}

private struct OutputDetailView: View {
    @EnvironmentObject private var model: AppModel
    let output: OutputRecord
    @State private var url: URL?
    @State private var preview: URL?
    @State private var error: String?
    var body: some View {
        List {
            Section {
                Label(output.filename, systemImage: "doc").font(.headline)
                Text(output.location).font(.footnote).foregroundStyle(.secondary)
                Text("\(ByteCountFormatter.string(fromByteCount: Int64(output.byteCount), countStyle: .file)) when created · \(output.createdAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                if let warning = output.warning { Text(warning).font(.footnote) }
                if let error { Text(error).font(.footnote).foregroundStyle(.secondary) }
            }
            if let url {
                Section {
                    if !["html", "htm", "svg"].contains(url.pathExtension.lowercased()) {
                        Button("Preview Files copy", systemImage: "doc.viewfinder") { preview = url }
                    }
                    ShareLink(item: url) { Label("Share Files copy", systemImage: "square.and.arrow.up") }
                    ExportDocumentButton(url: url, title: "Export another copy")
                }
            }
            Section { Text("Files can be changed or moved outside this app. The original save verification does not verify later edits or cloud synchronization.").font(.caption).foregroundStyle(.secondary) }
        }
        .navigationTitle(output.filename).navigationBarTitleDisplayMode(.inline)
        .quickLookPreview($preview)
        .task {
            do {
                guard let root = model.store?.outputsRoot else { return }
                url = try WorkspacePath.resolve(output.filename, inside: root)
            } catch { self.error = "This Files copy was moved or removed. The original may still be available in Library." }
        }
    }
}

struct ExportDocumentButton: View {
    let url: URL
    var title = "Save to Files"
    @State private var exporting = false
    @State private var result: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button(title, systemImage: "folder.badge.plus") { result = nil; exporting = true }
            if let result { Text(result).font(.caption).foregroundStyle(.secondary) }
        }
        .sheet(isPresented: $exporting, onDismiss: { if result == nil { result = "Export cancelled." } }) {
            DocumentExportPicker(url: url) { status in
                result = status == "completed" ? "Export completed. Cloud sync depends on the selected provider." : "Export cancelled."
                exporting = false
            }
        }
    }
}
