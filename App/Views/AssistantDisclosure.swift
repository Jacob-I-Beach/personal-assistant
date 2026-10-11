import SwiftUI

private struct ChatViewportKey: EnvironmentKey { static let defaultValue: ChatViewport? = nil }
extension EnvironmentValues {
    var chatViewport: ChatViewport? {
        get { self[ChatViewportKey.self] }
        set { self[ChatViewportKey.self] = newValue }
    }
}

/// Pin the tapped heading before changing height. Deeper levels gain indentation,
/// a quiet background and a leading rule instead of another identical chat row.
struct AssistantDisclosure<Content: View, Label: View>: View {
    @Environment(\.chatViewport) private var viewport
    @State private var expanded = false
    @State private var anchorID = UUID()
    var nested = false
    @ViewBuilder var content: () -> Content
    @ViewBuilder var label: () -> Label
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                viewport?.pinDisclosure(anchorID)
                AppFeedback.play(.selection)
                var transaction = Transaction(); transaction.disablesAnimations = true
                withTransaction(transaction) { expanded.toggle() }
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    label().frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                }.frame(minHeight: 38).contentShape(Rectangle())
            }.buttonStyle(QuietPressStyle()).accessibilityValue(expanded ? "Expanded" : "Collapsed")
                .background(alignment: .topLeading) { ChatScrollAnchor(id: anchorID).frame(width: 1, height: 1) }
            if expanded {
                content().frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 14).padding(.top, 8).padding(.bottom, 10)
                    .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 1).fill(Color.primary.opacity(0.1)).frame(width: 2).padding(.vertical, 8) }
            }
        }.padding(.horizontal, nested ? 12 : 0)
            .background(nested ? Color(uiColor: .secondarySystemBackground) : .clear, in: RoundedRectangle(cornerRadius: 12))
    }
}
