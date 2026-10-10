import AssistantCore
import CoreLocation
import Darwin
import Foundation
import os
import UIKit

enum NativeTools {
    static func definition(_ name: String, _ description: String, _ fields: [String: String]) -> ToolDefinition {
        ToolDefinition(name: name, description: description, parameters: .object([
            "type": .string("object"), "properties": .object(fields.mapValues { .object(["type": .string("string"), "description": .string($0)]) }),
            "required": .array(fields.keys.sorted().map(JSONValue.string)), "additionalProperties": .bool(false)
        ]))
    }
    static let device = definition("get_device_info", "Read current device model identifier, OS, memory, storage, battery and thermal state. No unique identifier, call history, account data or other apps' settings.", ["reason": "Short reason this information helps the user's task."])
    static let context = definition("get_app_context", "Read this app's actual context settings: selected model, memory and history access, location-context permission and fresh home weather if the user enabled it. Weather is a cached estimate with a timestamp, not a new measurement. This does not request permissions or start tracking.", ["reason": "Why current app context is relevant."])
    static let location = definition("get_current_location", "Read one foreground location fix for a relevant task. Reuses enabled location-context permission; otherwise presents native review. iOS permission still applies. Coordinates include accuracy and time. No continuous background tracking.", ["reason": "Explain why this task needs the user's current location."])
    static let pdf = definition("create_pdf", "Create an actual paginated PDF document on this iPhone from a title and Markdown text. Text layout only; no remote images or script execution. For calculated documents, use verified tool results.", ["filename": "A simple filename ending .pdf", "title": "Document title", "markdown": "Document body; converted to plain text with basic paragraph layout."])
    static let calendar = definition("prepare_calendar_event", "Present Apple's event editor with a proposed event. The user reviews and saves or cancels. Does not read other events and never silently adds one.", ["title": "Event title", "start": "ISO8601 date-time including time-zone offset", "end": "ISO8601 date-time including time-zone offset", "notes": "Optional details, or empty", "location": "Event location, or empty"])
    static let maps = definition("open_in_maps", "Legacy external place-search handoff, only when the user explicitly asks to open Maps. For directions prefer prepare_route: it keeps the preview and reply in-app, with a separate Open in Maps button. Opening Maps does not confirm navigation started.", ["query": "Place name or address to find."])
    static let route = definition("prepare_route", "Resolve and review places with Apple Maps, then calculate a route and display its native preview, distance and travel-time estimate in this conversation. Use this for directions instead of searching the web for addresses. The user confirms the destination. Does not leave the app or start navigation. Needs a connection to Apple; unavailable in Local only mode.", ["origin": "Place/address including city, or current_location for a reviewed foreground fix.", "destination": "Destination name/address including city if known. Do not invent a city.", "transport": "driving, walking, or cycling"])
    static let readRoute = definition("read_route", "Read a route prepared in this conversation and its recorded Maps handoff status. This does not refresh the estimate or inspect active navigation.", ["route_id": "Exact route_id from prepare_route."])
    static let phone = definition("prepare_phone_call", "Offer a phone number to the system dialer after user review. The user controls calling. Cannot read call history or inspect ongoing calls.", ["number": "International or local phone number, digits with optional leading plus.", "reason": "Why the user requested this call."])
    static let message = definition("compose_text_message", "Open the system message composer inside the app. The user reviews recipients and text and presses Send. Cannot read previous messages or send automatically.", ["recipients": "Comma-separated phone numbers, or empty so the user selects recipients.", "body": "Proposed message text."])
    static let definitions = [device, context, location, pdf, calendar, route, readRoute, maps, phone, message]
}

@MainActor
enum DeviceContext {
    static func snapshot() -> JSONValue {
        var system = utsname(); uname(&system)
        let identifier = Mirror(reflecting: system.machine).children.compactMap { $0.value as? Int8 }.filter { $0 != 0 }.map { String(UnicodeScalar(UInt8(bitPattern: $0))) }.joined()
        let process = ProcessInfo.processInfo, device = UIDevice.current
        let wasMonitoring = device.isBatteryMonitoringEnabled; device.isBatteryMonitoringEnabled = true
        defer { device.isBatteryMonitoringEnabled = wasMonitoring }
        let storage = (try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())[.systemFreeSize] as? NSNumber)?.doubleValue
        let thermal: String
        switch process.thermalState { case .nominal: thermal = "nominal"; case .fair: thermal = "fair"; case .serious: thermal = "serious"; case .critical: thermal = "critical"; @unknown default: thermal = "unknown" }
        return .object([
            "model_identifier": .string(identifier), "device_family": .string(device.model), "os": .string(device.systemName + " " + device.systemVersion),
            "physical_memory_bytes": .number(Double(process.physicalMemory)), "currently_available_process_memory_bytes": .number(Double(os_proc_available_memory())),
            "free_storage_bytes": storage.map(JSONValue.number) ?? .null, "thermal_state": .string(thermal),
            "low_power_mode": .bool(process.isLowPowerModeEnabled), "battery_fraction": device.batteryLevel < 0 ? .null : .number(Double(device.batteryLevel)),
            "time_zone": .string(TimeZone.current.identifier), "observed_at": .string(ISO8601DateFormatter().string(from: Date())),
            "limitations": .string("Available process memory is a changing OS estimate, not a guarantee that a model fits. Model identifier is a product class, not a unique device ID.")
        ])
    }
}

@MainActor
final class ForegroundLocation: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var waiter: CheckedContinuation<JSONValue, any Error>?
    private var requestID: UUID?
    private var timeout: Task<Void, Never>?
    private var requested = false
    override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyHundredMeters }
    var authorizationSummary: String {
        switch manager.authorizationStatus {
        case .notDetermined: "Not requested"
        case .authorizedWhenInUse: "Allowed while using the app"
        case .authorizedAlways: "Allowed by iOS; this app requests foreground fixes"
        case .denied: "Denied in iPhone Settings"
        case .restricted: "Restricted by iOS"
        @unknown default: "Unavailable"
        }
    }
    func read() async throws -> JSONValue {
        guard UIApplication.shared.applicationState == .active else { throw AssistantError.invalidTool("Location needs the app open in the foreground.") }
        guard waiter == nil else { throw AssistantError.busy }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                waiter = continuation; requested = false; requestID = id
                timeout = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(25))
                    guard !Task.isCancelled, self?.requestID == id else { return }
                    self?.finish(.failure(AssistantError.provider("A location fix did not arrive. Check Location Services and try again.")))
                }
                requestIfAuthorized()
            }
        } onCancel: { Task { @MainActor [weak self] in
            guard self?.requestID == id else { return }
            self?.finish(.failure(CancellationError()))
        } }
    }
    private func requestIfAuthorized() {
        guard waiter != nil else { return }
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            if !requested { requested = true; manager.requestLocation() }
        case .denied, .restricted: finish(.failure(AssistantError.provider("Location access is off for this app. You can change it in iPhone Settings.")))
        @unknown default: finish(.failure(AssistantError.provider("Location authorization is unavailable.")))
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { requestIfAuthorized() }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) { finish(.failure(error)) }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last, fix.horizontalAccuracy >= 0, abs(fix.timestamp.timeIntervalSinceNow) < 60 else {
            finish(.failure(AssistantError.provider("The available location was stale or lacked an accuracy estimate."))); return
        }
        finish(.success(.object(["latitude": .number(fix.coordinate.latitude), "longitude": .number(fix.coordinate.longitude),
            "horizontal_accuracy_meters": .number(fix.horizontalAccuracy), "observed_at": .string(ISO8601DateFormatter().string(from: fix.timestamp)),
            "precision": .string(manager.accuracyAuthorization == .fullAccuracy ? "full" : "reduced"), "source": .string("Core Location")])))
    }
    private func finish(_ result: Result<JSONValue, any Error>) {
        guard let continuation = waiter else { return }; waiter = nil; requested = false; requestID = nil
        timeout?.cancel(); timeout = nil; manager.stopUpdatingLocation()
        continuation.resume(with: result)
    }
}
