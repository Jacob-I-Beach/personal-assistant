import ActivityKit
import AssistantCore
import Foundation

@MainActor final class ReplyLiveActivity {
    private var currentID: String?
    private var onComputer = false
    private var pendingUpdate: Task<Void, Never>?
    private var endingIDs = Set<String>()
    private var lastTitle = ""
    private var lastPhase = "working"
    private var lastUpdate = Date.distantPast
    private var steps: [String] = []
    private var tokenUpdates: Task<Void, Never>?
    private var deviceUpdates: Task<Void, Never>?
    private var remoteJobID: String?
    private var remoteClient: CompanionClient?
    private var wantsNotifications = false
    private var externalPresentation = false
    private var lastContext: (conversationID: UUID, modelName: String, computer: Bool)?
    private(set) var remoteNotificationsAvailable = false

    func begin(conversationID: UUID, modelName: String, computer: Bool, reconnecting: Bool, externalPresentation: Bool = false) {
        tokenUpdates?.cancel(); deviceUpdates?.cancel(); remoteJobID = nil; remoteClient = nil; remoteNotificationsAvailable = false
        lastContext = (conversationID, modelName, computer)
        self.externalPresentation = externalPresentation
        if externalPresentation { useExternalPresentation(); return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        onComputer = computer; lastTitle = ""; lastUpdate = .distantPast; lastPhase = "working"
        let candidates = Activity<AssistantActivityAttributes>.activities.filter {
            $0.attributes.conversationID == conversationID.uuidString && ($0.activityState == .active || $0.activityState == .stale) && !$0.content.state.isReady
        }
        if reconnecting, let existing = candidates.first(where: { !endingIDs.contains($0.id) }) {
            currentID = existing.id; steps = existing.content.state.steps ?? []
            update("Continuing your reply"); return
        }
        steps = []
        let oldIDs = Activity<AssistantActivityAttributes>.activities.map(\.id).filter { !endingIDs.contains($0) }
        endingIDs.formUnion(oldIDs)
        let previous = pendingUpdate
        pendingUpdate = Task.detached {
            await previous?.value
            for id in oldIDs {
                if let activity = Activity<AssistantActivityAttributes>.activities.first(where: { $0.id == id }) { await activity.end(nil, dismissalPolicy: .immediate) }
            }
        }
        let attributes = AssistantActivityAttributes(conversationID: conversationID.uuidString, startedAt: Date(), onComputer: computer, modelName: modelName)
        let state = AssistantActivityAttributes.ContentState(title: "Preparing your reply", detail: "", phase: "working", updatedAt: Date(), steps: [], onComputer: computer)
        currentID = try? Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(180)), pushType: computer && RemotePushRegistration.environment != nil ? .token : nil).id
    }

    func attach(jobID: String, client: CompanionClient, notifications: Bool, externalPresentation: Bool = false) {
        if externalPresentation {
            self.externalPresentation = true; remoteJobID = jobID; remoteClient = client
            useExternalPresentation(); remoteNotificationsAvailable = notifications
            return
        }
        if self.externalPresentation, let context = lastContext {
            begin(conversationID: context.conversationID, modelName: context.modelName, computer: context.computer, reconnecting: true)
        }
        guard remoteJobID != jobID else { return }
        remoteJobID = jobID; remoteClient = client; wantsNotifications = notifications
        tokenUpdates?.cancel(); deviceUpdates?.cancel()
        guard RemotePushRegistration.environment != nil else { return }
        RemotePushRegistration.register()
        tokenUpdates = Task { [weak self] in
            guard let self else { return }
            await self.registerTokens()
            guard let id = self.currentID, let activity = Activity<AssistantActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
            for await _ in activity.pushTokenUpdates {
                if Task.isCancelled { return }
                await self.registerTokens()
            }
        }
        deviceUpdates = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: RemotePushRegistration.changed) {
                if Task.isCancelled { return }
                await self?.registerTokens()
            }
        }
    }
    private func useExternalPresentation() {
        tokenUpdates?.cancel(); deviceUpdates?.cancel(); currentID = nil
        let ids = Activity<AssistantActivityAttributes>.activities.map(\.id).filter { !endingIDs.contains($0) }
        endingIDs.formUnion(ids)
        let previous = pendingUpdate
        pendingUpdate = Task.detached {
            await previous?.value
            for id in ids {
                if let activity = Activity<AssistantActivityAttributes>.activities.first(where: { $0.id == id }) { await activity.end(nil, dismissalPolicy: .immediate) }
            }
        }
    }
    private func registerTokens() async {
        guard let job = remoteJobID, let client = remoteClient, let environment = RemotePushRegistration.environment,
              let topic = Bundle.main.bundleIdentifier else { return }
        let token = Activity<AssistantActivityAttributes>.activities.first(where: { $0.id == currentID })?.pushToken?.map { String(format: "%02x", $0) }.joined()
        var fields: [String: AssistantCore.JSONValue] = ["environment": .string(environment), "topic": .string(topic), "notifications": .bool(wantsNotifications)]
        if let token { fields["activity_token"] = .string(token) }
        if let device = RemotePushRegistration.deviceToken { fields["device_token"] = .string(device) }
        guard fields["activity_token"] != nil || fields["device_token"] != nil else { return }
        for delay in [0, 2, 5] {
            if Task.isCancelled { return }
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            do {
                let response = try await client.json("/v1/jobs/" + job + "/push", method: "POST", body: .object(fields))
                guard remoteJobID == job else { return }
                remoteNotificationsAvailable = response["delivery_configured"] == .bool(true) && fields["device_token"] != nil && wantsNotifications
                return
            }
            catch { /* The task continues even if APNs provisioning is not ready. */ }
        }
    }

    func update(_ title: String, waiting: Bool = false, reconnecting: Bool = false) {
        let phase = waiting ? "waiting" : reconnecting ? "reconnecting" : "working"
        guard let id = currentID, title != lastTitle || phase != lastPhase || Date().timeIntervalSince(lastUpdate) > 20 else { return }
        lastTitle = title; lastPhase = phase; lastUpdate = Date()
        if phase == "working", steps.last != title { steps.append(String(title.prefix(100))); steps = Array(steps.suffix(3)) }
        let state = AssistantActivityAttributes.ContentState(title: String(title.prefix(120)), detail: waiting ? "Open this chat to answer or review." : "", phase: phase, updatedAt: Date(), steps: steps, onComputer: onComputer)
        enqueue(id: id, state: state, end: false)
    }

    /// Deliver final UI state before releasing the app's execution window.
    /// A ready result remains available to open, without claiming work is ongoing.
    func finish(completed: Bool, detached: Bool, handingOff: Bool = false, waiting: Bool = false, keepReady: Bool = true) async {
        guard let id = currentID else { return }
        if handingOff { update("Continuing your reply"); return }
        // Server pushes remain authoritative when the UI subscriber goes away.
        if detached { await pendingUpdate?.value; return }
        if waiting { update("Your task needs attention", waiting: true); await pendingUpdate?.value; return }
        let state = AssistantActivityAttributes.ContentState(title: completed ? "Your reply is ready" : "Progress saved",
            detail: completed ? "Tap to open the answer and saved results." : "Open this chat to review and continue.",
            phase: completed ? "ready" : "paused", updatedAt: Date(), steps: steps, onComputer: onComputer, finishedAt: completed ? Date() : nil)
        lastPhase = state.phase
        let end = !completed || !keepReady
        if end { endingIDs.insert(id) }
        enqueue(id: id, state: state, end: end)
        await pendingUpdate?.value
        if end, currentID == id { currentID = nil }
    }

    func viewed(conversationID: UUID) async {
        // Reconstruct ready state from ActivityKit after a cold launch as well.
        let ids = Activity<AssistantActivityAttributes>.activities.filter {
            $0.attributes.conversationID == conversationID.uuidString && $0.content.state.isReady
        }.map(\.id)
        guard !ids.isEmpty else { return }
        endingIDs.formUnion(ids)
        let previous = pendingUpdate
        pendingUpdate = Task.detached {
            await previous?.value
            for id in ids {
                if let activity = Activity<AssistantActivityAttributes>.activities.first(where: { $0.id == id }) { await activity.end(nil, dismissalPolicy: .immediate) }
            }
        }
        await pendingUpdate?.value
        if let currentID, ids.contains(currentID) { self.currentID = nil }
    }

    private func enqueue(id: String, state: AssistantActivityAttributes.ContentState, end: Bool) {
        let previous = pendingUpdate
        // ActivityKit handles stay on one worker executor; state is Sendable.
        pendingUpdate = Task.detached {
            await previous?.value
            guard let activity = Activity<AssistantActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
            let content = ActivityContent(state: state, staleDate: state.isWorking ? Date().addingTimeInterval(75) : nil)
            if end { await activity.end(content, dismissalPolicy: .immediate) }
            else { await activity.update(content) }
        }
    }
}
