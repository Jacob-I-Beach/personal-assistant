import ActivityKit
import SwiftUI
import WidgetKit

@main struct AssistantActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AssistantActivityAttributes.self) { context in
            AssistantActivityCard(attributes: context.attributes, state: context.state, stale: context.isStale)
                .activityBackgroundTint(Color(white: 0.065)).activitySystemActionForegroundColor(.white)
                .widgetURL(destination(context.attributes.conversationID))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        AssistantActivityMark().frame(width: 28, height: 28)
                        Text(context.attributes.modelName ?? "Personal Assistant").font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                    }.padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    AssistantActivityIndicator(state: context.state, stale: context.isStale).padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    AssistantActivityBody(attributes: context.attributes, state: context.state, stale: context.isStale)
                        .padding(.horizontal, 8).padding(.top, 4).padding(.bottom, 10)
                }
            } compactLeading: {
                AssistantActivityMark().frame(width: 23, height: 23)
            } compactTrailing: {
                AssistantActivityIndicator(state: context.state, stale: context.isStale)
            } minimal: {
                if context.state.isReady || context.state.isWaiting {
                    AssistantActivityIndicator(state: context.state, stale: context.isStale)
                } else { AssistantActivityMark().frame(width: 23, height: 23) }
            }.widgetURL(destination(context.attributes.conversationID)).keylineTint(context.state.isReady ? .green : .indigo)
        }
    }
    private func destination(_ id: String) -> URL? { URL(string: "personalassistant://task/" + id) }
}
