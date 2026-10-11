import ActivityKit
import Foundation

@MainActor final class ReplyLiveActivity {
    private var current: Activity<AssistantActivityAttributes>?
    private var lastTitle = ""
    private var lastUpdate = Date.distantPast
    func begin(conversationID: UUID, computer: Bool) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if let existing = Activity<AssistantActivityAttributes>.activities.first(where: { $0.attributes.conversationID == conversationID.uuidString }) { current = existing; return }
        let attributes = AssistantActivityAttributes(conversationID: conversationID.uuidString, startedAt: Date(), onComputer: computer)
        let state = AssistantActivityAttributes.ContentState(title: "Preparing your task", detail: computer ? "Your computer will carry the work." : "Working on your iPhone", phase: "working", updatedAt: Date())
        current = try? Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(60)), pushType: nil)
    }
    func update(_ title: String, waiting: Bool = false) {
        guard let current, title != lastTitle || Date().timeIntervalSince(lastUpdate) > 30 else { return }
        lastTitle = title; lastUpdate = Date()
        let state = AssistantActivityAttributes.ContentState(title: String(title.prefix(100)), detail: waiting ? "Open your chat to continue." : current.attributes.onComputer ? "Task owned by your computer" : "Progress is saved as work continues", phase: waiting ? "waiting" : "working", updatedAt: Date())
        Task { await current.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(60))) }
    }
    func finish(completed: Bool, detached: Bool) {
        guard let current else { return }
        if detached { update("Task on your computer"); return }
        let state = AssistantActivityAttributes.ContentState(title: completed ? "Your reply is ready" : "Progress saved", detail: completed ? "Open your chat for the answer and files." : "Open your chat to review and continue.", phase: completed ? "completed" : "waiting", updatedAt: Date())
        Task { await current.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(completed ? 120 : 1800))) }
        self.current = nil
    }
}
