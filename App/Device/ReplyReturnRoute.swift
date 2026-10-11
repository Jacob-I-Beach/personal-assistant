import Foundation

/// One-shot return destination for work that the user left running. It contains
/// no transcript, account information or Health data and never starts a model.
@MainActor
enum ReplyReturnRoute {
    private static let key = "assistant.reply.returnDestination"
    static func remember(_ conversationID: UUID) {
        UserDefaults.standard.set(["conversation": conversationID.uuidString, "time": Date().timeIntervalSince1970], forKey: key)
    }
    static func take() -> UUID? {
        guard let value = UserDefaults.standard.dictionary(forKey: key) else { return nil }
        UserDefaults.standard.removeObject(forKey: key)
        guard let time = value["time"] as? Double, (0...86_400).contains(Date().timeIntervalSince1970 - time),
              let raw = value["conversation"] as? String else { return nil }
        return UUID(uuidString: raw)
    }
    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}
