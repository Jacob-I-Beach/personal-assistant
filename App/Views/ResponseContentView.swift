import AssistantCore
import SwiftUI

struct ActiveWorkRow: View {
    let title: String
    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            ProgressView().controlSize(.mini).frame(width: 16, height: 16)
            Text(title).font(.caption.weight(.medium)).lineLimit(1)
        }.foregroundStyle(.secondary).frame(minHeight: 22).padding(.vertical, 3)
            .accessibilityElement(children: .combine).accessibilityIdentifier("active-tool-row")
    }
}

struct ResponseContentView: View {
    let message: Message
    private var parts: [ResponsePart] { message.displayParts }
    private struct PartGroup: Identifiable {
        var offset: Int
        var parts: [ResponsePart]
        var id: String { parts[0].id }
    }
    private var groups: [PartGroup] {
        var result: [PartGroup] = []
        for (index, part) in parts.enumerated() {
            if part.web != nil, result.last?.parts.last?.web != nil { result[result.count - 1].parts.append(part) }
            else { result.append(PartGroup(offset: index, parts: [part])) }
        }
        return result
    }
    var body: some View {
        if parts.isEmpty {
            AssistantMarkdown(text: message.citationMarkdown)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(groups) { group in
                    if group.parts.count > 1 {
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(group.parts) { part in
                                    if let activity = part.web { WebActivityView(activity: resolved(activity)) }
                                }
                            }.padding(.top, 10)
                        } label: {
                            Label("Web research · \(group.parts.count) searches", systemImage: "globe").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        }.tint(.secondary).transaction { $0.animation = nil }
                    } else if let part = group.parts.first, part.kind == .text {
                        let offset = parts.prefix(group.offset).reduce(0) { $0 + $1.citations.count }
                        AssistantMarkdown(text: Message.citationMarkdown(text: part.text, citations: part.citations, startingAt: offset))
                            .foregroundStyle(Color.primary)
                            .accessibilityIdentifier("response-text-\(group.offset)")
                    } else if let activity = group.parts.first?.web {
                        WebActivityView(activity: resolved(activity))
                    }
                }
            }
        }
    }
    private func resolved(_ activity: WebActivity) -> WebActivity {
        var value = activity
        if message.state != .streaming && value.isRunning { value.status = "incomplete" }
        return value
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
            HStack(alignment: .center, spacing: 7) {
                Group {
                    if activity.isRunning { ProgressView().controlSize(.mini) }
                    else { Image(systemName: activity.isSuccessful ? "globe" : "exclamationmark.circle") }
                }.frame(width: 16, height: 16)
                Text(activity.title).font(.caption.weight(.medium)).lineLimit(1)
                if let page = activity.sources.first { Text(page.url.host ?? "").font(.caption2).lineLimit(1) }
            }.foregroundStyle(.secondary).frame(minHeight: 22).padding(.vertical, 3)
        }
        .tint(.secondary)
        .font(.caption).transaction { $0.animation = nil }
        .accessibilityIdentifier("web-activity")
    }
}
