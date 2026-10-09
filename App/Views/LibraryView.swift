import AssistantCore
import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    private var latestArtifacts: [ArtifactRecord] {
        let oldVersions = Set(model.artifacts.compactMap(\.previousRevisionID))
        return model.artifacts.filter { !oldVersions.contains($0.id) }
    }
    var body: some View {
        NavigationStack {
            List {
                Section { NavigationLink { CaptureLibraryView() } label: { Label("Captures · \(model.captures.count)", systemImage: "viewfinder") } }
                Section("Your files") {
                    if latestArtifacts.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Useful work, kept here").font(.headline)
                            Text("Documents, tables, scripts, and other files created in a conversation will appear here. You can edit, share, and revisit them.").foregroundStyle(.secondary)
                        }.padding(.vertical, 10)
                    }
                    ForEach(latestArtifacts) { artifact in
                        NavigationLink { ArtifactDetailView(artifact: artifact) } label: { ArtifactCard(artifact: artifact) }
                    }
                }
            }
            .navigationTitle("Library")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .refreshable { await model.refresh() }
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
    let artifact: ArtifactRecord
    @State private var text = ""
    @State private var editing = false
    @State private var exportURL: URL?
    @State private var saving = false
    var body: some View {
        Group {
            if editing { TextEditor(text: $text).font(.body.monospaced()).padding(10).accessibilityLabel("Edit artifact") }
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
                        saving = true
                        Task { await model.reviseArtifact(artifact, content: text); saving = false; editing = false }
                    }.disabled(saving || text == artifact.content)
                } else {
                    Button("Edit", systemImage: "pencil") { editing = true }
                    if let exportURL { ShareLink(item: exportURL) { Image(systemName: "square.and.arrow.up") } }
                }
            }
        }
        .task { text = artifact.content; exportURL = await model.artifactURL(artifact) }
    }
}
