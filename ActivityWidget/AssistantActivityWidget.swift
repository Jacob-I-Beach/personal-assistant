import ActivityKit
import SwiftUI
import WidgetKit

@main struct AssistantActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AssistantActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    AssistantActivityMark().frame(width: 38, height: 38)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Personal Assistant").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        Text(title(context)).font(.headline).lineLimit(2).contentTransition(.numericText())
                    }
                    Spacer(minLength: 4)
                    phaseSymbol(context)
                }
                progress(context, maximumSteps: 2)
            }.padding(18).environment(\.colorScheme, .dark)
                .activityBackgroundTint(Color(white: 0.075)).activitySystemActionForegroundColor(.white)
                .widgetURL(destination(context.attributes.conversationID))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { AssistantActivityMark().frame(width: 32, height: 32).padding(.leading, 6) }
                DynamicIslandExpandedRegion(.trailing) { phaseSymbol(context).padding(.trailing, 6) }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(title(context)).font(.headline).lineLimit(2)
                        progress(context)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8).padding(.bottom, 10)
                }
            } compactLeading: {
                AssistantActivityMark().frame(width: 24, height: 24)
            } compactTrailing: {
                phaseSymbol(context).frame(width: 26)
            } minimal: {
                AssistantActivityMark().frame(width: 24, height: 24)
            }.widgetURL(destination(context.attributes.conversationID)).keylineTint(.indigo)
        }
    }
    @ViewBuilder private func phaseSymbol(_ context: ActivityViewContext<AssistantActivityAttributes>) -> some View {
        if context.state.phase == "completed" {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.mint).contentTransition(.symbolEffect(.replace))
        } else if context.state.phase == "waiting" {
            Image(systemName: "bubble.left.and.bubble.right.fill").foregroundStyle(.orange)
        } else if context.isStale {
            Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.secondary)
        } else {
            Image(systemName: "waveform").foregroundStyle(.indigo, .white)
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: true)
        }
    }
    @ViewBuilder private func progress(_ context: ActivityViewContext<AssistantActivityAttributes>, maximumSteps: Int = 3) -> some View {
        if context.state.phase == "working", !context.isStale {
            let steps = Array((context.state.steps ?? []).suffix(maximumSteps))
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(spacing: 8) {
                    Image(systemName: index == steps.count - 1 ? "circle.fill" : "circle").font(.system(size: 9, weight: .semibold)).foregroundStyle(index == steps.count - 1 ? Color.indigo : Color.secondary)
                    Text(step).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            HStack {
                Text("In progress").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(context.attributes.startedAt, style: .timer).font(.caption2.monospacedDigit()).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
            }
        } else {
            Text(context.isStale && context.state.phase == "working" ? "Open your chat to sync the latest progress." : context.state.detail)
                .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
        }
    }
    private func title(_ context: ActivityViewContext<AssistantActivityAttributes>) -> String {
        context.isStale && context.state.phase == "working" ? "Your task is saved" : context.state.title
    }
    private func destination(_ id: String) -> URL? { URL(string: "personalassistant://task/" + id) }
}

private struct AssistantActivityMark: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: geometry.size.width * 0.28).fill(LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "ellipsis.bubble.fill").font(.system(size: geometry.size.width * 0.6, weight: .medium)).foregroundStyle(.white)
            }
        }.accessibilityLabel("Personal Assistant")
    }
}
