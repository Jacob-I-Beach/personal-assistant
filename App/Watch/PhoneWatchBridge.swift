import AssistantCore
import Foundation
@preconcurrency import WatchConnectivity

@MainActor
final class PhoneWatchBridge: NSObject, WCSessionDelegate {
    var onRequest: ((WatchRequest) async -> Void)?
    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self; WCSession.default.activate()
    }
    func send(_ reply: WatchReply) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              WCSession.default.isPaired, let data = try? WatchWire.encode(reply) else { return }
        let payload: [String: Any] = ["assistantReply": data]
        try? WCSession.default.updateApplicationContext(payload)
        if WCSession.default.isReachable { WCSession.default.sendMessage(payload, replyHandler: nil, errorHandler: nil) }
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { receive(message) }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) { receive(userInfo) }
    private nonisolated func receive(_ payload: [String: Any]) {
        guard let data = payload["assistantRequest"] as? Data, let request = try? WatchWire.decode(WatchRequest.self, data: data) else { return }
        Task { @MainActor [weak self] in await self?.onRequest?(request) }
    }
}
