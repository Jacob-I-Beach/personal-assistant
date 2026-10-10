import AssistantCore
import SwiftUI

struct ResponseContentView: View {
    let message: Message
    private var parts: [ResponsePart] { message.displayParts }
    var body: some View {
        if parts.isEmpty {
            AssistantMarkdown(text: message.citationMarkdown)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(parts.enumerated()), id: \.element.id) { index, part in
                    if part.kind == .text {
                        let offset = parts.prefix(index).reduce(0) { $0 + $1.citations.count }
                        AssistantMarkdown(text: Message.citationMarkdown(text: part.text, citations: part.citations, startingAt: offset))
                            .foregroundStyle(Color.primary)
                            .accessibilityIdentifier("response-text-\(index)")
                    } else if let activity = part.web {
                        WebActivityView(activity: activity)
                    }
                }
            }
        }
    }
}

struct WebActivityView: View {
    let activity: WebActivity
    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(activity.queries.enumerated()), id: \.offset) { _, query in
                    Label(query, systemImage: "magnifyingglass").font(.subheadline).textSelection(.enabled)
                }
                if let pattern = activity.pattern { Text("Find: \(pattern)").font(.subheadline) }
                ForEach(activity.sources) { source in
                    Link(destination: source.url) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(source.title).font(.subheadline).multilineTextAlignment(.leading)
                            Text(source.url.host ?? "").font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if activity.sources.isEmpty {
                    Text("The provider did not return a page list for this activity. Any cited sources appear with the answer.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.top, 10)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                if activity.isRunning { ProgressView().controlSize(.small) }
                else { Image(systemName: activity.isSuccessful ? "globe" : "exclamationmark.circle").padding(.top, 2) }
                Text(activity.title).font(.caption.weight(.medium))
                if let page = activity.sources.first { Text(page.url.host ?? "").font(.caption2).lineLimit(1) }
            }.foregroundStyle(.secondary).padding(.vertical, 3)
        }
        .tint(.secondary)
        .font(.caption).transaction { $0.animation = nil }
        .accessibilityIdentifier("web-activity")
    }
}
