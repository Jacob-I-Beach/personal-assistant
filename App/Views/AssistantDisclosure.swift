import SwiftUI

private struct ChatViewportKey: EnvironmentKey { static let defaultValue: ChatViewport? = nil }
private struct DisclosureDepthKey: EnvironmentKey { static let defaultValue = 0 }
extension EnvironmentValues {
    var chatViewport: ChatViewport? {
        get { self[ChatViewportKey.self] }
        set { self[ChatViewportKey.self] = newValue }
    }
    var disclosureDepth: Int {
        get { self[DisclosureDepthKey.self] }
        set { self[DisclosureDepthKey.self] = newValue }
    }
}

/// Pin the tapped heading before changing height. Deeper levels gain indentation,
/// a quiet background and a leading rule instead of another identical chat row.
struct AssistantDisclosure<Content: View, Label: View>: View {
    @Environment(\.chatViewport) private var viewport
    @Environment(\.disclosureDepth) private var depth
    @State private var expanded = false
    @State private var anchorID = UUID()
    var nested = false
    var identifier: String? = nil
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
                }.frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(QuietPressStyle()).accessibilityValue(expanded ? "Expanded" : "Collapsed")
                .accessibilityIdentifier(identifier ?? "assistant-disclosure")
                .background(alignment: .topLeading) { ChatScrollAnchor(id: anchorID).frame(width: 1, height: 1) }
            if expanded {
                content().frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.disclosureDepth, depth + 1)
                    .padding(.leading, depth > 1 ? 8 : 12).padding(.top, 2).padding(.bottom, 10)
                    .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 1).fill(Color.primary.opacity(0.12)).frame(width: 2).padding(.vertical, 8) }
            }
        }.padding(.horizontal, nested || depth > 0 ? 10 : 0)
            .background(nested || depth > 0 ? Color.primary.opacity(0.035) : .clear, in: RoundedRectangle(cornerRadius: 14))
            .overlay { if nested || depth > 0 { RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.055), lineWidth: 0.5).allowsHitTesting(false) } }
    }
}
