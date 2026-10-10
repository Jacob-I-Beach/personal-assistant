import UIKit

/// A bounded UIKit completion window, not a permanent background service.
@MainActor
final class ResponseCompletionWindow {
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    func begin(expired: @escaping @MainActor () -> Void) {
        end()
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Finish assistant reply") { [weak self] in
            Task { @MainActor in
                self?.end()
                expired()
            }
        }
    }
    func end() {
        guard identifier != .invalid else { return }
        let old = identifier; identifier = .invalid
        UIApplication.shared.endBackgroundTask(old)
    }
}
