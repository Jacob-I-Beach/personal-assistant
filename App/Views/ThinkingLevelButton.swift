import AssistantCore
import SwiftUI

struct ThinkingLevelButton: View {
    let effort: ReasoningEffort?
    let action: () -> Void
    private var fraction: CGFloat { effort.map { CGFloat((ReasoningEffort.allCases.firstIndex(of: $0) ?? 1) + 1) / 5 } ?? 0 }
    var body: some View {
        Button { AppFeedback.play(.selection); action() } label: {
            Image(systemName: "brain").font(.system(size: 25)).foregroundStyle(.secondary)
                .overlay(alignment: .bottom) {
                    Image(systemName: "brain").font(.system(size: 25)).foregroundStyle(.indigo)
                        .mask(alignment: .bottom) { Rectangle().frame(height: 28 * fraction) }
                }.frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(QuietPressStyle()).accessibilityLabel("Response settings")
            .accessibilityValue(effort.map { "Thinking \($0.title)" } ?? "Context controls")
            .accessibilityHint("Change thinking effort and working context for this model")
    }
}
