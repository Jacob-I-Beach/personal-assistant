import SwiftUI

/// These are the same components used by the widget extension and native visual
/// fixtures. Only observed state is animated; no synthetic completion percentage.
struct AssistantActivityMark: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: geometry.size.width * 0.28)
                    .fill(LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "ellipsis.bubble.fill")
                    .font(.system(size: geometry.size.width * 0.59, weight: .medium)).foregroundStyle(.white)
            }
        }.accessibilityLabel("Personal Assistant")
    }
}

struct AssistantActivityIndicator: View {
    let state: AssistantActivityAttributes.ContentState
    var stale = false
    @Environment(\.isLuminanceReduced) private var luminanceReduced
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Group {
            if state.isReady {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).contentTransition(.symbolEffect(.replace))
                    .accessibilityLabel("Reply ready")
            } else if state.isWaiting {
                Image(systemName: "bubble.left.and.bubble.right.fill").foregroundStyle(.orange).accessibilityLabel("Needs your attention")
            } else if state.phase == "paused" {
                Image(systemName: "pause.circle").foregroundStyle(.secondary).accessibilityLabel("Progress saved")
            } else if stale || state.phase == "reconnecting" {
                Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.secondary).accessibilityLabel("Updating progress")
            } else if luminanceReduced || reduceMotion {
                Image(systemName: "circle.dotted").foregroundStyle(.white).accessibilityLabel("Working")
            } else {
                ProgressView().progressViewStyle(.circular).tint(.white).controlSize(.small).accessibilityLabel("Working")
            }
        }.font(.system(size: 19, weight: .medium)).frame(width: 24, height: 24)
    }
}

struct AssistantActivityBody: View {
    let attributes: AssistantActivityAttributes
    let state: AssistantActivityAttributes.ContentState
    var stale = false
    var detailLines = 2
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(state.headline(stale: stale)).font(.headline).foregroundStyle(.white).lineLimit(2)
                .contentTransition(.numericText())
            if state.isWorking && !stale, let earlier = (state.steps ?? []).dropLast().last, earlier != state.title {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath").font(.caption2)
                    Text(earlier).lineLimit(1)
                }.font(.caption).foregroundStyle(.secondary)
            } else if !state.isWorking || stale {
                Text(state.supportingText(stale: stale)).font(.caption).foregroundStyle(.secondary).lineLimit(detailLines)
            }
            HStack(spacing: 8) {
                Text(state.isReady ? "Ready to open" : state.isWaiting ? "Waiting for you" : stale || state.phase == "reconnecting" ? "Connection updating" : "In progress")
                    .foregroundStyle(state.isReady ? Color.green : Color.secondary)
                Spacer(minLength: 8)
                if let finished = state.finishedAt {
                    let elapsed = max(0, Int(finished.timeIntervalSince(attributes.startedAt)))
                    Text(String(format: "%d:%02d", elapsed / 60, elapsed % 60)).monospacedDigit().foregroundStyle(.secondary)
                } else if state.isWorking && !stale {
                    Text(attributes.startedAt, style: .timer).monospacedDigit().multilineTextAlignment(.trailing).foregroundStyle(.secondary)
                }
            }.font(.caption2)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AssistantActivityCard: View {
    let attributes: AssistantActivityAttributes
    let state: AssistantActivityAttributes.ContentState
    var stale = false
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                AssistantActivityMark().frame(width: 28, height: 28)
                Text(attributes.modelName ?? "Personal Assistant").font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 4)
                AssistantActivityIndicator(state: state, stale: stale)
            }
            AssistantActivityBody(attributes: attributes, state: state, stale: stale, detailLines: 1)
        }.padding(.horizontal, 18).padding(.vertical, 14).environment(\.colorScheme, .dark)
    }
}
