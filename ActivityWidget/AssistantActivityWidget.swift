import ActivityKit
import SwiftUI
import WidgetKit

@main struct AssistantActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AssistantActivityAttributes.self) { context in
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "brain").font(.title2).foregroundStyle(.indigo).padding(11).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Personal Assistant").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: context.attributes.onComputer ? "desktopcomputer" : "iphone").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(title(context)).font(.headline).lineLimit(2)
                    Text(detail(context)).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
            }.padding(18).activityBackgroundTint(Color(white: 0.10)).activitySystemActionForegroundColor(.white)
                .widgetURL(destination(context.attributes.conversationID))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: "brain").font(.title2).foregroundStyle(.indigo).padding(.leading, 5) }
                DynamicIslandExpandedRegion(.trailing) { Image(systemName: context.attributes.onComputer ? "desktopcomputer" : "iphone").foregroundStyle(.secondary) }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title(context)).font(.headline)
                        Text(detail(context)).font(.subheadline).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 5).padding(.bottom, 8)
                }
            } compactLeading: {
                Image(systemName: "brain").foregroundStyle(.indigo)
            } compactTrailing: {
                Image(systemName: context.state.phase == "completed" ? "checkmark" : context.state.phase == "waiting" ? "bubble.left" : "ellipsis").font(.caption)
            } minimal: {
                Image(systemName: "brain").foregroundStyle(.indigo)
            }.widgetURL(destination(context.attributes.conversationID)).keylineTint(.indigo)
        }
    }
    private func title(_ context: ActivityViewContext<AssistantActivityAttributes>) -> String {
        context.isStale && context.state.phase == "working" ? (context.attributes.onComputer ? "Task on your computer" : "Open to check your task") : context.state.title
    }
    private func detail(_ context: ActivityViewContext<AssistantActivityAttributes>) -> String {
        context.isStale && context.state.phase == "working" ? "Open the chat for the latest saved progress." : context.state.detail
    }
    private func destination(_ id: String) -> URL? { URL(string: "personalassistant://task/" + id) }
}
