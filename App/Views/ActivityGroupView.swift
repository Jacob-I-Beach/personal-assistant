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
        AssistantDisclosure {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(categories) { group in
                    if group.messages.count > 1 {
                        AssistantDisclosure(nested: true) {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(group.messages) { WorkReceiptView(message: $0) }
                            }.padding(.top, 10)
                        } label: {
                            Text("\(group.name) · \(group.messages.count)").font(.subheadline)
                        }
                    } else if let message = group.messages.first { WorkReceiptView(message: message) }
                }
            }.padding(.top, 12)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: messages.contains(where: { $0.toolFailureDescription != nil }) ? "exclamationmark.circle" : "checkmark.circle")
                Text("Activity").fontWeight(.medium)
                Text("\(messages.count) \(messages.count == 1 ? "step" : "steps")").foregroundStyle(.secondary)
                if messages.contains(where: { $0.toolFailureDescription != nil }) { Text("Needs attention").foregroundStyle(.secondary) }
            }.font(.caption).padding(.vertical, 6)
        }
        .tint(.secondary).foregroundStyle(.secondary).transaction { $0.animation = nil }
        .accessibilityIdentifier("activity-group")
    }
}
