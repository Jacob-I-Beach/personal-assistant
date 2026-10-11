import Foundation
import UserNotifications

/// Local attention notifications work with personal signing; remote push is not assumed.
@MainActor
final class TaskAttentionService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = TaskAttentionService()
    var onOpen: (@MainActor (UUID) async -> Void)?
    private var queuedConversation: UUID?
    private var notificationIDs: [UUID: Set<String>] = [:]
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }
    func requestPermission() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--ui-") }) { return }
        #endif
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }
    func notify(conversationID: UUID, title: String, explanation: String) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = title; content.body = explanation; content.sound = .default
        content.threadIdentifier = conversationID.uuidString
        content.userInfo = ["conversation_id": conversationID.uuidString]
        clear(conversationID)
        let identifier = "task-" + conversationID.uuidString + "-" + UUID().uuidString
        notificationIDs[conversationID, default: []].insert(identifier)
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }
    func clear(_ id: UUID) {
        let identifiers = Array(notificationIDs.removeValue(forKey: id) ?? [])
        guard !identifiers.isEmpty else { return }
        Task.detached(priority: .utility) {
            let center = UNUserNotificationCenter.current()
            center.removeDeliveredNotifications(withIdentifiers: identifiers)
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }
    func openQueued() async {
        guard let id = queuedConversation, let onOpen else { return }
        queuedConversation = nil; await onOpen(id)
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let raw = response.notification.request.content.userInfo["conversation_id"] as? String,
              let id = UUID(uuidString: raw) else { return }
        await receive(id, notificationID: response.notification.request.identifier)
    }
    private func receive(_ id: UUID, notificationID: String) async {
        notificationIDs[id, default: []].insert(notificationID)
        clear(id)
        if let onOpen { await onOpen(id) } else { queuedConversation = id }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [] }
}
