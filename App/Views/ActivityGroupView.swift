import AssistantCore
import SwiftUI

struct ActivityGroupView: View {
    @EnvironmentObject private var model: AppModel
    let messages: [Message]
    private struct Category: Identifiable {
        var name: String
        var messages: [Message]
        var id: String { name }
    }
    private var categories: [Category] {
        var groups: [Category] = []
        for message in messages {
            let name = ChatTimeline.category(ChatTimeline.toolName(for: message, in: model.conversation.messages))
            if let index = groups.firstIndex(where: { $0.name == name }) { groups[index].messages.append(message) }
            else { groups.append(Category(name: name, messages: [message])) }
        }
        return groups
    }
    var body: some View {
        AssistantDisclosure(identifier: "activity-group") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(categories) { group in
                    if group.messages.count > 1 {
                        AssistantDisclosure(nested: true, identifier: "activity-category-" + group.name) {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(group.messages) { WorkReceiptView(message: $0) }
                            }.padding(.top, 10)
                        } label: {
                            ActivitySummaryLabel(summary: ActivitySummaries.tools(group.messages, in: model.conversation.messages))
                        }
                    } else if let message = group.messages.first { WorkReceiptView(message: message) }
                }
            }.padding(.top, 12)
        } label: {
            ActivitySummaryLabel(summary: ActivitySummaries.tools(messages, in: model.conversation.messages))
        }
        .tint(.secondary).foregroundStyle(.secondary).transaction { $0.animation = nil }
        .accessibilityIdentifier("activity-group")
    }
}

struct ActivitySummaryLabel: View {
    let summary: ActivitySummary
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if summary.running { ProgressView().controlSize(.mini) }
                else { Image(systemName: summary.symbol).font(.system(size: 14, weight: .medium)) }
            }.frame(width: 18, height: 20).foregroundStyle(summary.needsAttention ? Color.orange : Color.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.title).font(.subheadline.weight(.medium)).foregroundStyle(Color.primary.opacity(0.85)).lineLimit(2).multilineTextAlignment(.leading)
                if !summary.detail.isEmpty { Text(summary.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
        }.padding(.vertical, 8).accessibilityElement(children: .combine)
    }
}
