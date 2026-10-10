import AssistantCore
import SwiftUI

struct FileEditReviewView: View {
    let proposal: FileEditProposal
    var readOnly = false
    let complete: (String) -> Void
    @State private var selection = 0
    private var lines: [TextDiffLine] { TextDiffLine.compare(before: proposal.original, after: proposal.replacement) }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(proposal.file.relativePath).font(.headline)
                    Text(readOnly ? "These are saved snapshots from this change. You can inspect or copy the original; the current file may have changed since." : "The app will check that this file still matches the original before applying these changes. The previous contents stay in edit history.")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("Preview", selection: $selection) {
                        Text("Changes").tag(0); Text("Original").tag(1); Text("Revised").tag(2)
                    }.pickerStyle(.segmented)
                }.padding()
                ScrollView([.vertical, .horizontal]) {
                    if selection == 0 {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(lines) { line in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(line.kind == .added ? "+" : line.kind == .removed ? "−" : " ")
                                    Text(line.text.isEmpty ? " " : line.text)
                                }
                                .font(.caption.monospaced())
                                .padding(.horizontal, 12).padding(.vertical, 3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(line.kind == .added ? Color.green.opacity(0.12) : line.kind == .removed ? Color.red.opacity(0.10) : .clear)
                            }
                        }.textSelection(.enabled)
                    } else {
                        Text(selection == 1 ? proposal.original : proposal.replacement).font(.caption.monospaced()).textSelection(.enabled).padding()
                    }
                }
            }
            .navigationTitle(readOnly ? "Saved change" : "Review changes").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(readOnly ? "Done" : "Cancel") { complete("cancelled") } }
                ToolbarItem(placement: .confirmationAction) {
                    if readOnly { Button("Copy original", systemImage: "doc.on.doc") { UIPasteboard.general.string = proposal.original } }
                    else { Button("Apply changes") { complete("approved") }.fontWeight(.semibold) }
                }
            }
        }.interactiveDismissDisabled(!readOnly)
    }
}
