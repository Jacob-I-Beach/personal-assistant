import Foundation
import UserNotifications

/// Local attention notifications work with personal signing; remote push is not assumed.
@MainActor
final class TaskAttentionService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = TaskAttentionService()
    var onOpen: (@MainActor (UUID) async -> Void)?
    private var queuedConversation: UUID?
    private var notificationIDs: [UUID: Set<String>] = [:]
    private var pendingClear: Task<Void, Never>?
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        if !TaskPresentationPolicy.isEnabled {
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        }
    }
    func requestPermission() async {
        guard TaskPresentationPolicy.isEnabled else { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--ui-") }) { return }
        #endif
        let center = UNUserNotificationCenter.current()
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        RemotePushRegistration.register()
    }
    func notify(conversationID: UUID, title: String, explanation: String) async {
        guard TaskPresentationPolicy.isEnabled else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = title; content.body = explanation; content.sound = .default
        content.threadIdentifier = conversationID.uuidString
        content.userInfo = ["conversation_id": conversationID.uuidString]
        await clear(conversationID).value
        let identifier = "task-" + conversationID.uuidString
        notificationIDs[conversationID, default: []].insert(identifier)
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }
    @discardableResult func clear(_ id: UUID) -> Task<Void, Never> {
        let identifiers = Array((notificationIDs.removeValue(forKey: id) ?? []).union(["task-" + id.uuidString]))
        let previous = pendingClear
        let task = Task.detached(priority: .utility) {
            await previous?.value
            let center = UNUserNotificationCenter.current()
            let older = await center.deliveredNotifications().filter { $0.request.content.threadIdentifier == id.uuidString }.map { $0.request.identifier }
            center.removeDeliveredNotifications(withIdentifiers: Array(Set(identifiers + older)))
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
        pendingClear = task
        return task
    }
    func openQueued() async {
        guard let id = queuedConversation, let onOpen else { return }
        queuedConversation = nil; await onOpen(id)
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = (response.notification.request.content.userInfo["conversation_id"] as? String).flatMap(UUID.init(uuidString:))
        let shouldOpen = response.actionIdentifier == UNNotificationDefaultActionIdentifier
        let notificationID = response.notification.request.identifier
        let completion = MainThreadNotificationCompletion<Void> { _ in completionHandler() }
        Task { @MainActor in
            defer { completion.finish(()) }
            guard shouldOpen, let id else { return }
            await receive(id, notificationID: notificationID)
        }
    }
    private func receive(_ id: UUID, notificationID: String) async {
        notificationIDs[id, default: []].insert(notificationID)
        clear(id)
        if let onOpen { await onOpen(id) } else { queuedConversation = id }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let completion = MainThreadNotificationCompletion(completionHandler)
        Task { @MainActor in completion.finish([]) }
    }
}

/// UIKit's notification-return snapshot requires its completion on the main thread.
/// The callback enters through a nonisolated delegate, then is used only on MainActor.
final class MainThreadNotificationCompletion<Value: Sendable>: @unchecked Sendable {
    private var callback: ((Value) -> Void)?
    init(_ callback: @escaping (Value) -> Void) { self.callback = callback }
    @MainActor func finish(_ value: Value) {
        let action = callback; callback = nil; action?(value)
    }
}
