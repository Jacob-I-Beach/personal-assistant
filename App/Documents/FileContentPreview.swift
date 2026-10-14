import AssistantCore
import QuickLook
import SwiftUI

struct FileContentPreview: View {
    let file: WorkspaceFile
    let url: URL
    @State private var showSource = false
    private var ext: String { url.pathExtension.lowercased() }
    private var sourceOnly: Bool { ["html", "htm", "svg", "xml", "js", "ts", "py", "swift", "sh", "ps1", "json", "css"].contains(ext) }
    var body: some View {
        Group {
            if ["csv", "tsv"].contains(ext) && !showSource {
                VStack(alignment: .leading, spacing: 12) {
                    let preview = DelimitedPreview(file.text, delimiter: ext == "tsv" ? "\t" : ",")
                    ScrollView([.horizontal, .vertical]) {
                        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                            ForEach(Array(preview.rows.enumerated()), id: \.offset) { index, row in
                                GridRow {
                                    Text("\(index + 1)").font(.caption).foregroundStyle(.secondary)
                                    ForEach(Array(row.enumerated()), id: \.offset) { column, value in
                                        Text(value).font(.subheadline.monospaced()).textSelection(.enabled).frame(maxWidth: 240, alignment: .leading)
                                            .accessibilityLabel("Row \(index + 1), column \(column + 1): \(value)")
                                    }
                                }
                                Divider()
                            }
                        }.padding(20)
                    }
                    HStack { if preview.truncated { Text("Preview shortened; the original file is unchanged.").font(.caption).foregroundStyle(.secondary) }; Spacer(); Button("View source") { showSource = true } }.padding(.horizontal, 20)
                }
            } else if sourceOnly || ["txt", "md", "csv", "tsv"].contains(ext) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if sourceOnly { Text("Source preview · this content is not executed").font(.caption).foregroundStyle(.secondary) }
                        if ext == "md" { AssistantMarkdown(text: String(file.text.prefix(100_000))) }
                        else { Text(String(file.text.prefix(100_000))).font(.body.monospaced()).textSelection(.enabled) }
                        if file.text.count > 100_000 { Text("Text preview shortened. Share or export the original for the complete file.").font(.caption).foregroundStyle(.secondary) }
                        if showSource { Button("Back to table") { showSource = false } }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
                }
            } else if QLPreviewController.canPreview(url as NSURL) {
                ReadOnlyFilePreview(url: url)
            } else {
                ContentUnavailableView("Preview unavailable", systemImage: "doc", description: Text("The original is available through Share. File info includes any extracted text and its limitations."))
            }
        }.accessibilityIdentifier("file-content-preview")
    }
}

private struct ReadOnlyFilePreview: UIViewControllerRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController(); controller.dataSource = context.coordinator; controller.delegate = context.coordinator; return controller
    }
    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        if context.coordinator.url != url { context.coordinator.url = url; controller.reloadData() }
    }
    @MainActor final class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
        var url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem { url as NSURL }
        func previewController(_ controller: QLPreviewController, editingModeFor previewItem: any QLPreviewItem) -> QLPreviewItemEditingMode { .disabled }
    }
}
