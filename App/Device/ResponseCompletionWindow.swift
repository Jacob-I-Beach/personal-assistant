import BackgroundTasks
import UIKit

/// User-started network/CPU work. No location/audio mode or GPU entitlement is requested.
@MainActor
final class ResponseCompletionWindow {
    static let shared = ResponseCompletionWindow(registerContinued: true)
    private var shortWindow: UIBackgroundTaskIdentifier = .invalid
    private var continued: BGContinuedProcessingTask?
    private var requestID: String?
    private var expiration: (@MainActor (Bool) -> Void)?
    private var registered = false
    private var units: Int64 = 0
    private var lastUpdate = Date.distantPast
    private var prefix: String { (Bundle.main.bundleIdentifier ?? "dev.jacob.personalassistant") + ".reply." }
    init(registerContinued: Bool = false) {
        guard registerContinued else { return }
        registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: prefix + "*", using: .main) { [weak self] task in
            MainActor.assumeIsolated {
                guard let self, let task = task as? BGContinuedProcessingTask, self.requestID == task.identifier else {
                    task.setTaskCompleted(success: false); return
                }
                self.continued = task
                task.progress.totalUnitCount = -1 // Unknown length; never invent a percentage or ETA.
                task.progress.completedUnitCount = self.units
                let identifier = task.identifier
                task.expirationHandler = { [weak self] in
                    Task { @MainActor in
                        guard let self, self.requestID == identifier else { return }
                        let handler = self.expiration
                        self.end(success: false)
                        handler?(true)
                    }
                }
                self.endShortWindow()
            }
        }
    }
    func begin(allowContinued: Bool = false, expired: @escaping @MainActor (Bool) -> Void) {
        end(success: false); expiration = expired; units = 0; lastUpdate = .distantPast
        shortWindow = UIApplication.shared.beginBackgroundTask(withName: "Finish assistant reply") { [weak self] in
            Task { @MainActor in
                guard let self, self.continued == nil else { return }
                let handler = self.expiration; self.end(success: false); handler?(false)
            }
        }
        guard allowContinued, registered, UIApplication.shared.applicationState == .active else { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--ui-") }) { return }
        #endif
        let id = prefix + UUID().uuidString
        requestID = id
        let request = BGContinuedProcessingTaskRequest(identifier: id, title: "Personal Assistant", subtitle: "Working on your request")
        request.strategy = .fail
        do { try BGTaskScheduler.shared.submit(request) }
        catch { requestID = nil }
    }
    func update(completedUnits: Int, subtitle: String) {
        units = max(units, Int64(completedUnits))
        guard Date().timeIntervalSince(lastUpdate) >= 1, let continued else { return }
        lastUpdate = Date()
        continued.progress.completedUnitCount = units
        continued.updateTitle("Personal Assistant", subtitle: String(subtitle.prefix(90)))
    }
    func status(_ text: String) { continued?.updateTitle("Personal Assistant", subtitle: String(text.prefix(90))) }
    func end(success: Bool = true) {
        let oldID = requestID; requestID = nil; expiration = nil
        if let task = continued {
            continued = nil
            if success { task.progress.totalUnitCount = units + 1; task.progress.completedUnitCount = units + 1 }
            task.setTaskCompleted(success: success)
        } else if let oldID { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: oldID) }
        endShortWindow()
    }
    private func endShortWindow() {
        guard shortWindow != .invalid else { return }
        let old = shortWindow; shortWindow = .invalid
        UIApplication.shared.endBackgroundTask(old)
    }
}
