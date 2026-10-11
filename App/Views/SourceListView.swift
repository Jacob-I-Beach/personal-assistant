import AssistantCore
import SwiftUI

struct SourceListView: View {
    let citations: [WebCitation]
    private var sources: [CitationSource] { CitationSource.group(citations) }
    var body: some View {
        Group {
            if sources.count > 3 {
                AssistantDisclosure { rows.padding(.top, 10) } label: {
                    Label("\(sources.count) sources", systemImage: "link").font(.subheadline.weight(.medium))
                }
                .tint(.secondary)
                .padding(14).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                .accessibilityIdentifier("collapsible-sources")
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sources").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    rows
                }.padding(.vertical, 6)
            }
        }
    }
    private var rows: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(sources) { source in
                Link(destination: source.citation.url) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(source.numbers.map { "[\($0)]" }.joined(separator: " ")) \(source.citation.title)")
                            .font(.footnote).multilineTextAlignment(.leading)
                        Text(source.citation.url.host ?? "").font(.caption2).foregroundStyle(.secondary)
                    }.padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
