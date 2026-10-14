import AssistantCore
import SwiftUI

struct DelimitedContentView: View {
    let text: String
    var delimiter: Character = ","
    @State private var source = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(source ? "Show table" : "View source") { source.toggle() }.padding(.horizontal, 20)
            if source { Text(String(text.prefix(100_000))).font(.body.monospaced()).textSelection(.enabled).padding(20) }
            else {
                let preview = DelimitedPreview(text, delimiter: delimiter)
                ScrollView(.horizontal) {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                        ForEach(Array(preview.rows.enumerated()), id: \.offset) { index, row in
                            GridRow {
                                Text("\(index + 1)").font(.caption).foregroundStyle(.secondary)
                                ForEach(Array(row.enumerated()), id: \.offset) { column, value in
                                    Text(value).font(.subheadline.monospaced()).textSelection(.enabled).frame(maxWidth: 240, alignment: .leading)
                                        .accessibilityLabel("Row \(index + 1), column \(column + 1): \(value)")
                                }
                            }
                        }
                    }.padding(20)
                }
                if preview.truncated { Text("Preview shortened; the complete file is preserved.").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20) }
            }
        }.accessibilityIdentifier("delimited-content-preview")
    }
}
