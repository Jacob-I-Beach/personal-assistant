import Foundation

/// Local alerts do not technically require APNs. They are deliberately paused,
/// together with task activities, until the user's developer-signing rollout.
@MainActor enum TaskPresentationPolicy {
    static var isEnabled: Bool { RemotePushRegistration.environment != nil }
}
