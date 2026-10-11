import BackgroundTasks
import AssistantCore
import UIKit

/// User-started network/CPU work. No location/audio mode or GPU entitlement is requested.
@MainActor
final class ResponseCompletionWindow {
    static let shared = ResponseCompletionWindow(registerContinued: true)
    private var shortWindow: UIBackgroundTaskIdentifier = .invalid
    private var continued: BGContinuedProcessingTask?
    private var requestID: String?
    private var expiration: (@MainActor (Bool) -> Void)?
    private let supportsContinued: Bool
    private var units: Int64 = 0
    private var lastUpdate = Date.distantPast
    private var lastDiagnostic = Date.distantPast
    private var progressFlush: Task<Void, Never>?
    private var latestStatus = "Working on your request"
    private var diagnosticState = "idle"
    private var diagnosticCode: Int?
    private var turnID: UUID?
    private var prefix: String {
        // Personal signing can rewrite the bundle identifier. Use the family
        // actually permitted by the installed Info.plist, not a guessed prefix.
        if let family = (Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String])?.first(where: { $0.hasSuffix(".reply.*") }) { return String(family.dropLast()) }
        return (Bundle.main.bundleIdentifier ?? "dev.jacob.personalassistant") + ".reply."
    }
    init(registerContinued: Bool = false) {
        supportsContinued = registerContinued
    }
    private func register(_ id: String) -> Bool {
        // Continued-processing handlers are registered for each concrete request immediately
        // before submission; the Info.plist wildcard permits the family, not a literal * job.
        // This callback is explicitly delivered on .main. Keep its main-actor
        // isolation; the BGTask object must not be transferred between actors.
        BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: .main) { [weak self] task in
            MainActor.assumeIsolated {
                guard let self, let task = task as? BGContinuedProcessingTask, self.requestID == task.identifier else {
                    task.setTaskCompleted(success: false); return
                }
                self.continued = task
                self.record("accepted")
                task.updateTitle("Personal Assistant", subtitle: self.latestStatus)
                task.progress.totalUnitCount = -1 // Unknown length; never invent a percentage or ETA.
                task.progress.completedUnitCount = self.units
                let identifier = task.identifier
                task.expirationHandler = { @Sendable [weak self] in
                    Task { @MainActor in
                        guard let self, self.requestID == identifier else { return }
                        let handler = self.expiration
                        self.record("system_expired_or_cancelled")
                        self.end(success: false, recordEnd: false)
                        handler?(true)
                    }
                }
                self.endShortWindow()
            }
        }
    }
    func begin(allowContinued: Bool = false, expired: @escaping @MainActor (Bool) -> Void) {
        end(success: false, recordEnd: false); expiration = expired; units = 0; lastUpdate = .distantPast
        latestStatus = "Preparing your request"; diagnosticCode = nil; turnID = nil; record("preparing")
        shortWindow = UIApplication.shared.beginBackgroundTask(withName: "Finish assistant reply") { [weak self] in
            Task { @MainActor in
                guard let self, self.continued == nil else { return }
                let handler = self.expiration; self.record("short_window_expired"); self.end(success: false, recordEnd: false); handler?(false)
            }
        }
        guard allowContinued, supportsContinued, UIApplication.shared.applicationState == .active else { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--ui-") }) { return }
        #endif
        let id = prefix + UUID().uuidString
        guard register(id) else { record("registration_failed"); return }
        requestID = id
        let request = BGContinuedProcessingTaskRequest(identifier: id, title: "Personal Assistant", subtitle: "Working on your request")
        request.strategy = .fail
        record("submitting")
        BGTaskScheduler.shared.submitTaskRequest(request) { @Sendable [weak self] error in
            let code = (error as NSError?)?.code
            Task { @MainActor in
                guard let self, self.requestID == id else { return }
                if let code { self.requestID = nil; self.diagnosticCode = code; self.record("submission_failed") }
            }
        }
    }
    func received(bytes: Int) {
        guard bytes > 0, requestID != nil || shortWindow != .invalid else { return }
        units += Int64(min(bytes, 64 * 1024 * 1024))
        // Stream activity and tool output can arrive before answer text. Report
        // those real bytes directly; silence never advances this counter.
        if Date().timeIntervalSince(lastUpdate) >= 0.3 { publishProgress() }
        else if progressFlush == nil {
            progressFlush = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                self?.progressFlush = nil; self?.publishProgress()
            }
        }
    }
    func identifyTurn(_ id: UUID) {
        guard turnID != id else { return }; turnID = id; record(diagnosticState)
    }
    private func publishProgress() {
        guard let continued else { return }
        lastUpdate = Date(); continued.progress.completedUnitCount = units
        if Date().timeIntervalSince(lastDiagnostic) >= 8 { record("receiving") }
    }
    func status(_ text: String) {
        guard latestStatus != text else { return }; latestStatus = text
        continued?.updateTitle("Personal Assistant", subtitle: String(text.prefix(90)))
    }
    func waitingForAttention(question: Bool) {
        let message = question ? "Your answer is needed" : "Ready for your review"
        continued?.updateTitle("Personal Assistant", subtitle: message)
        record(question ? "waiting_for_answer" : "waiting_for_review")
        // Finishing this processing segment is successful. The saved user task
        // remains waiting; holding a CPU task open would make iOS report failure.
        end(success: true, recordEnd: false)
    }
    func recordFailure(_ error: any Error) {
        if let error = error as? URLError {
            diagnosticCode = error.code.rawValue
            record(error.code == .timedOut ? "network_timeout" : "network_interrupted")
        }
    }
    func end(success: Bool = true, recordEnd: Bool = true) {
        progressFlush?.cancel(); progressFlush = nil
        if recordEnd, requestID != nil || shortWindow != .invalid,
           success || !["network_timeout", "network_interrupted"].contains(diagnosticState) { record(success ? "completed" : "interrupted") }
        let oldID = requestID; requestID = nil; expiration = nil
        if let task = continued {
            continued = nil
            if success { task.progress.totalUnitCount = units + 1; task.progress.completedUnitCount = units + 1 }
            task.setTaskCompleted(success: success)
        } else if let oldID { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: oldID) }
        if let oldID { BGTaskScheduler.shared.unregisterForTask(withIdentifier: oldID) }
        endShortWindow()
    }
    private func record(_ state: String) {
        diagnosticState = state; lastDiagnostic = Date()
        // Counts and lifecycle only: no prompt, model output, task/account IDs,
        // locations or arbitrary error descriptions go into a diagnostic export.
        let value: [String: Any] = ["turn_key": turnID?.uuidString ?? "", "state": state, "processed_bytes": units, "recorded_at": ISO8601DateFormatter().string(from: lastDiagnostic), "submission_error_code": diagnosticCode ?? 0]
        UserDefaults.standard.set(value, forKey: "assistant.background.lastDiagnostic")
    }
    static func diagnostic(for turnID: UUID) -> JSONValue {
        guard let value = UserDefaults.standard.dictionary(forKey: "assistant.background.lastDiagnostic"), value["turn_key"] as? String == turnID.uuidString else { return .object(["state": .string("No background record is available for this task.")]) }
        return .object(["state": .string(value["state"] as? String ?? "unknown"), "processed_bytes": .number((value["processed_bytes"] as? NSNumber)?.doubleValue ?? 0), "recorded_at": .string(value["recorded_at"] as? String ?? ""), "submission_error_code": .number((value["submission_error_code"] as? NSNumber)?.doubleValue ?? 0)])
    }
    private func endShortWindow() {
        guard shortWindow != .invalid else { return }
        let old = shortWindow; shortWindow = .invalid
        UIApplication.shared.endBackgroundTask(old)
    }
}
