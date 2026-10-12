import ActivityKit
import Foundation

@MainActor final class ReplyLiveActivity {
    private var currentID: String?
    private var onComputer = false
    private var pendingUpdate: Task<Void, Never>?
    private var endingIDs = Set<String>()
    private var lastTitle = ""
    private var lastUpdate = Date.distantPast
    private var steps: [String] = []
    func begin(conversationID: UUID, computer: Bool, reconnecting: Bool) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        onComputer = computer; lastTitle = ""; lastUpdate = .distantPast
        if !reconnecting { steps = [] }
        let candidates = Activity<AssistantActivityAttributes>.activities.filter { $0.attributes.conversationID == conversationID.uuidString && ($0.activityState == .active || $0.activityState == .stale) }
        if reconnecting, let existing = candidates.first(where: { !endingIDs.contains($0.id) }) { currentID = existing.id; update("Continuing your reply"); return }
        let oldIDs = Activity<AssistantActivityAttributes>.activities.map(\.id).filter { !endingIDs.contains($0) }
        if !oldIDs.isEmpty {
            endingIDs.formUnion(oldIDs)
            let previous = pendingUpdate
            pendingUpdate = Task.detached {
                await previous?.value
                for id in oldIDs {
                    if let activity = Activity<AssistantActivityAttributes>.activities.first(where: { $0.id == id }) { await activity.end(nil, dismissalPolicy: .immediate) }
                }
            }
        }
        let attributes = AssistantActivityAttributes(conversationID: conversationID.uuidString, startedAt: Date(), onComputer: computer)
        let state = AssistantActivityAttributes.ContentState(title: "Preparing your reply", detail: "Your progress stays with this chat", phase: "working", updatedAt: Date(), steps: [], onComputer: computer)
        currentID = try? Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(60)), pushType: nil).id
    }
    func update(_ title: String, waiting: Bool = false) {
        guard let id = currentID, title != lastTitle || Date().timeIntervalSince(lastUpdate) > 30 else { return }
        lastTitle = title; lastUpdate = Date()
        if steps.last != title { steps.append(String(title.prefix(70))); steps = Array(steps.suffix(3)) }
        let state = AssistantActivityAttributes.ContentState(title: String(title.prefix(100)), detail: waiting ? "Open the chat to answer or review." : "Your progress stays with this chat", phase: waiting ? "waiting" : "working", updatedAt: Date(), steps: steps, onComputer: onComputer)
        let previous = pendingUpdate
        // Only immutable state and an identifier cross executors. ActivityKit's
        // non-Sendable handle is found and used entirely in the worker task.
        pendingUpdate = Task.detached {
            await previous?.value
            guard let activity = Activity<AssistantActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
            await activity.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(60)))
        }
    }
    func finish(completed: Bool, detached: Bool) {
        guard let id = currentID else { return }
        if detached { update("Continuing your reply"); return }
        let state = AssistantActivityAttributes.ContentState(title: completed ? "Your reply is ready" : "Progress saved", detail: completed ? "Open your chat for the answer and files." : "Open your chat to review and continue.", phase: completed ? "completed" : "waiting", updatedAt: Date())
        let previous = pendingUpdate
        endingIDs.insert(id)
        pendingUpdate = Task.detached {
            await previous?.value
            guard let activity = Activity<AssistantActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
            await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: completed ? .after(Date().addingTimeInterval(60)) : .immediate)
        }
        currentID = nil
    }
}
