import SwiftUI
@preconcurrency import WatchConnectivity

@main
struct AssistantWatchApp: App {
    @StateObject private var bridge = WatchAssistantBridge()
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Assistant").font(.title2.weight(.semibold))
                        TextField("Ask or capture a thought", text: $bridge.draft)
                        Button("Ask on iPhone", systemImage: "arrow.up") { bridge.send() }
                            .buttonStyle(.borderedProminent).disabled(bridge.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if let reply = bridge.reply {
                            Text(bridge.title(for: reply.state)).font(.headline)
                            Text(reply.message).font(.body)
                            if !reply.modelName.isEmpty { Text(reply.modelName).font(.caption2).foregroundStyle(.secondary) }
                        } else { Text(bridge.connectionNote).font(.footnote).foregroundStyle(.secondary) }
                    }.padding(.horizontal, 6)
                }.navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

@MainActor
final class WatchAssistantBridge: NSObject, ObservableObject, WCSessionDelegate {
    @Published var draft = ""
    @Published var reply: WatchReply?
    @Published var connectionNote = "Open the iPhone app to complete setup. Requests can wait until your phone is available."
    private var pendingID: UUID?
    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: "assistant-watch-reply") { reply = try? WatchWire.decode(WatchReply.self, data: data) }
        if let id = UserDefaults.standard.string(forKey: "assistant-watch-pending") { pendingID = UUID(uuidString: id) }
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self; WCSession.default.activate()
    }
    func send() {
        guard WCSession.default.activationState == .activated, !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            connectionNote = "The connection is preparing. Try again in a moment."; return
        }
        let request = WatchRequest(text: draft, conversationID: reply?.conversationID)
        guard request.isValid(), let data = try? WatchWire.encode(request) else { connectionNote = "This request is too long for Watch. Continue on iPhone."; return }
        pendingID = request.id; UserDefaults.standard.set(request.id.uuidString, forKey: "assistant-watch-pending")
        reply = WatchReply(requestID: request.id, conversationID: request.conversationID, state: .queued,
                           message: "Waiting for the iPhone app. Open it if a reply doesn't arrive.", modelName: "")
        let payload: [String: Any] = ["assistantRequest": data]
        // Durable queued delivery plus the fast live path. The iPhone deduplicates by request ID.
        WCSession.default.transferUserInfo(payload)
        if WCSession.default.isReachable { WCSession.default.sendMessage(payload, replyHandler: nil, errorHandler: nil) }
        draft = ""
    }
    func title(for state: WatchReply.State) -> String {
        switch state { case .queued: "Sent"; case .needsPhone: "Continue on iPhone"; case .working: "Working"; case .complete: "Ready"; case .failed: "Needs attention" }
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let data = session.receivedApplicationContext["assistantReply"] as? Data
        if let data { receive(data) }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let data = message["assistantReply"] as? Data { receive(data) }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let data = applicationContext["assistantReply"] as? Data { receive(data) }
    }
    private nonisolated func receive(_ data: Data) {
        guard let response = try? WatchWire.decode(WatchReply.self, data: data) else { return }
        Task { @MainActor [weak self] in
            guard let self, self.pendingID == response.requestID else { return }
            self.reply = response; UserDefaults.standard.set(data, forKey: "assistant-watch-reply")
        }
    }
}
