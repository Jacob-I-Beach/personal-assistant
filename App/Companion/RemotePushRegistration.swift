import AssistantCore
import UIKit
import Security

/// APNs registration is enabled only by the provisioned developer build.
/// The personal-signing build continues to run tasks without claiming push delivery.
@MainActor
final class RemotePushRegistration: NSObject, UIApplicationDelegate {
    static var deviceToken: String?
    static let changed = Notification.Name("AssistantRemotePushChanged")
    static var environment: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "AssistantPushEnvironment") as? String
        return ["development", "production"].contains(value ?? "") ? value : nil
    }
    static func register() {
        guard environment != nil else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
        Self.deviceToken = token.map { String(format: "%02x", $0) }.joined()
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Self.deviceToken = nil
        // Do not mix notification provisioning errors into a model task's status.
    }
}
