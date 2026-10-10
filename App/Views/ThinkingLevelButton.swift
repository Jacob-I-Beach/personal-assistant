import AssistantCore
import SwiftUI

struct ThinkingLevelButton: View {
    let effort: ReasoningEffort
    let action: () -> Void
    private var fraction: CGFloat { CGFloat((ReasoningEffort.allCases.firstIndex(of: effort) ?? 1) + 1) / 5 }
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(effort == .max ? Color.black : Color(uiColor: .tertiarySystemFill))
                if effort == .max {
                    Text("Max").font(.system(size: 9, weight: .semibold)).foregroundStyle(.white)
                } else {
                    ThinkingFill(fraction: fraction).fill(Color.gray.opacity(0.7))
                }
                Circle().strokeBorder(Color.secondary, lineWidth: 1.2)
            }.frame(width: 25, height: 25).frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("Thinking effort, \(effort.title)")
            .accessibilityValue(effort.title).accessibilityHint("Choose the thinking effort for the next reply")
    }
}
private struct ThinkingFill: Shape {
    let fraction: CGFloat
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        path.move(to: center)
        path.addArc(center: center, radius: min(rect.width, rect.height) / 2, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * Double(fraction)), clockwise: false)
        path.closeSubpath()
        return path
    }
}
