import SwiftUI
import UIKit

@MainActor
enum AppFeedback {
    enum Event { case selection, sent, copied, reply, saved, question }
    static var enabled = true
    private static var last = Date.distantPast
    private static var questionTask: Task<Void, Never>?
    static func play(_ event: Event) {
        guard enabled, UIApplication.shared.applicationState == .active else { return }
        // A question can follow the first reply chunk immediately. Its distinct
        // three-tap cue must take priority over the ordinary tap debounce.
        switch event {
        case .question: break
        default: guard Date().timeIntervalSince(last) > 0.09 else { return }
        }
        last = Date()
        switch event {
        case .selection: UISelectionFeedbackGenerator().selectionChanged()
        case .sent: UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.3)
        case .copied: UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.3)
        case .reply: UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.4)
        case .saved: UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.25)
        case .question:
            questionTask?.cancel()
            questionTask = Task { @MainActor in
                let generator = UIImpactFeedbackGenerator(style: .soft)
                for intensity in [0.3, 0.2, 0.3] {
                    guard !Task.isCancelled, enabled, UIApplication.shared.applicationState == .active else { return }
                    generator.impactOccurred(intensity: intensity)
                    try? await Task.sleep(for: .milliseconds(110))
                }
            }
        }
    }
}

/// A visible press response without changing the control's layout or tap target.
struct QuietPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.58 : 1)
            .background(configuration.isPressed ? Color.primary.opacity(0.065) : .clear, in: RoundedRectangle(cornerRadius: 11))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct MessageActionButton: View {
    let title: String
    let icon: String
    var confirmation: String?
    let action: () -> Void
    @State private var confirmed = false
    @State private var confirmationTask: Task<Void, Never>?
    var body: some View {
        Button {
            action(); AppFeedback.play(confirmation == nil ? .selection : .copied)
            if confirmation != nil {
                confirmationTask?.cancel()
                confirmed = true
                UIAccessibility.post(notification: .announcement, argument: confirmation)
                confirmationTask = Task {
                    try? await Task.sleep(for: .seconds(4))
                    guard !Task.isCancelled else { return }; confirmed = false
                }
            }
        } label: {
            Image(systemName: confirmed ? "checkmark" : icon)
                .font(.system(size: 16, weight: .regular)).frame(width: 44, height: 44)
                .contentTransition(.symbolEffect(.replace))
        }.buttonStyle(QuietPressStyle())
            .accessibilityLabel(confirmed ? confirmation ?? title : title)
            .overlay(alignment: .top) {
                if confirmed, let confirmation {
                    Text(confirmation).font(.caption2.weight(.medium)).padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.regularMaterial, in: Capsule()).fixedSize().offset(y: -23).allowsHitTesting(false)
                }
            }
            .onDisappear { confirmationTask?.cancel() }
    }
}
