import SwiftUI
import VisionKit
import AssistantCore

struct ComputerConnectionView: View {
    var openedTask: ((String) -> Void)?
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var showScanner = false
    @State private var manualCode = ""
    @State private var pairing = false
    @State private var state: String?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Your assistant keeps working", systemImage: "desktopcomputer").font(.title3.weight(.semibold))
                    Text("Your computer manages connected tasks from the moment you send them. It adds files, computation, browser and desktop tools when useful, and keeps the same work saved while your iPhone is away.").foregroundStyle(.secondary)
                }
                if let connection = model.settings.companion {
                    Section("Connected computer") {
                        Label(connection.name, systemImage: "checkmark.shield")
                        Toggle("Keep connected tasks on this computer", isOn: Binding(get: { model.settings.useComputer }, set: { enabled in
                            var next = model.settings; next.useComputer = enabled
                            do { try model.saveSettings(next); AppFeedback.play(.selection) } catch { self.error = error.localizedDescription }
                        })).disabled(model.isRunning)
                        Text("The selected GPT stays the same. This computer keeps each accepted task running, saves its progress and supplies computer tools when needed. Keep it awake and online. Local models run on this iPhone.").font(.footnote).foregroundStyle(.secondary)
                        Button("Check connection", systemImage: "arrow.clockwise") { Task { await check(connection) } }
                        Button("Update network connection", systemImage: "qrcode.viewfinder") { showScanner = true }
                            .disabled(pairing || !DataScannerViewController.isSupported || model.isRunning)
                        Text("Scan a new code from the same PC to use its private away-from-home address. Your pairing and saved tasks stay connected.").font(.footnote).foregroundStyle(.secondary)
                        NavigationLink { ComputerTasksView(openedTask: openedTask) } label: { Label("Tasks & schedules", systemImage: "clock.arrow.circlepath") }
                        if let state { Text(state).font(.subheadline).foregroundStyle(.secondary) }
                        Button("Disconnect this iPhone", role: .destructive) {
                            do {
                                var next = model.settings; next.companion = nil; next.useComputer = false
                                try model.saveSettings(next); try CredentialStore.remove(account: connection.credentialAccount)
                            } catch { self.error = error.localizedDescription }
                        }.disabled(model.isRunning)
                    }
                } else {
                    Section("Connect once") {
                        Text("Open Personal Assistant Computer on your PC, sign in to ChatGPT, then choose Connect iPhone. Scan the code it shows.")
                        Button("Scan computer code", systemImage: "qrcode.viewfinder") { showScanner = true }
                            .disabled(pairing || !DataScannerViewController.isSupported || model.isRunning)
                        DisclosureGroup("Enter a connection code") {
                            TextField("Paste the code from your computer", text: $manualCode, axis: .vertical).lineLimit(2...5).textInputAutocapitalization(.never).autocorrectionDisabled()
                            Button("Connect") { Task { await pair(manualCode) } }.disabled(manualCode.isEmpty || pairing || model.isRunning)
                        }
                        if pairing { ProgressView("Connecting to your computer…") }
                    }
                }
                Section("What happens while you’re away") {
                    Label("The PC keeps the task and its results", systemImage: "checkmark.circle")
                    Label("Phone actions wait for your iPhone", systemImage: "iphone")
                    Label("Return to the same chat to catch up", systemImage: "bubble.left.and.bubble.right")
                    Text("Use the same network, or a private VPN connection to your PC when away. A powered-off phone cannot display fresh activity; your computer can still finish the task.").font(.footnote).foregroundStyle(.secondary)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }.navigationTitle("Computer")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .sheet(isPresented: $showScanner) {
                    NavigationStack {
                        ComputerCodeScanner { code in showScanner = false; Task { await pair(code) } }
                            .navigationTitle("Scan computer code")
                            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showScanner = false } } }
                    }
                }
        }
    }
    private func pair(_ code: String) async {
        guard !pairing else { return }; pairing = true; error = nil
        defer { pairing = false }
        do {
            if let current = model.settings.companion, let payload = try? JSONValue.parse(code),
               payload["server_id"] == .string(current.serverID), payload["certificate_sha256"] == .string(current.certificateSHA256),
               let address = payload["base_url"]?.stringValue, let url = URL(string: address) {
                var updated = current; updated.baseURL = url
                let client = try CompanionClient(baseURL: url, fingerprint: current.certificateSHA256, token: CredentialStore.read(account: current.credentialAccount))
                let info = try await client.json("/v1/capabilities")
                guard info["profile"]?["profileId"] == .string(current.profileID) else { throw AssistantError.provider("Reconnect the original ChatGPT account on your computer.") }
                var next = model.settings; next.companion = updated
                try model.saveSettings(next); manualCode = ""; AppFeedback.play(.saved); await check(updated); return
            }
            let (connection, token) = try await CompanionClient.pair(code, deviceName: "My iPhone")
            try CredentialStore.save(token, account: connection.credentialAccount)
            var next = model.settings
            let previousContext = model.contextBudget(for: next)?.selectedInputTokens
            next.companion = connection; next.useComputer = true
            if let previousContext, next.contextTokensByModel[next.contextPreferenceKey] == nil { next.contextTokensByModel[next.contextPreferenceKey] = previousContext }
            try model.saveSettings(next); manualCode = ""; AppFeedback.play(.saved)
            await check(connection)
        } catch { self.error = error.localizedDescription }
    }
    private func check(_ connection: CompanionConnection) async {
        do {
            let client = try CompanionClient(baseURL: connection.baseURL, fingerprint: connection.certificateSHA256, token: CredentialStore.read(account: connection.credentialAccount))
            let info = try await client.json("/v1/capabilities")
            try model.applyComputerAccount(info["profile"] ?? .null, connection: connection)
            state = info["profile"]?["status"] == .string("connected") ? (info["computation_ready"] == .bool(true) ? "ChatGPT, Python and document tools are ready." : "ChatGPT is connected. Open the computer setup to finish computation tools.") : "Sign in to ChatGPT on your computer."
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

private struct ComputerCodeScanner: UIViewControllerRepresentable {
    var found: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(found: found) }
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced,
            recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false, isPinchToZoomEnabled: true, isGuidanceEnabled: true, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning(); return scanner
    }
    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}
    @MainActor final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var found: (String) -> Void
        var finished = false
        init(found: @escaping (String) -> Void) { self.found = found }
        func dataScanner(_ scanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !finished else { return }
            for item in addedItems { if case .barcode(let code) = item, let text = code.payloadStringValue {
                finished = true; scanner.stopScanning(); found(text); return
            } }
        }
    }
}
