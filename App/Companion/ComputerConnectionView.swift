import SwiftUI
import VisionKit
import AssistantCore

struct ComputerConnectionView: View {
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
                    Label("Let your computer carry the work", systemImage: "desktopcomputer").font(.title3.weight(.semibold))
                    Text("Long replies and document work continue on your PC when your iPhone locks or leaves the app. Your PC needs to stay awake and connected.").foregroundStyle(.secondary)
                }
                if let connection = model.settings.companion {
                    Section("Connected computer") {
                        Label(connection.name, systemImage: "checkmark.shield")
                        Toggle("Run ChatGPT tasks on this computer", isOn: Binding(get: { model.settings.useComputer }, set: { enabled in
                            var next = model.settings; next.useComputer = enabled
                            do { try model.saveSettings(next); AppFeedback.play(.selection) } catch { self.error = error.localizedDescription }
                        })).disabled(model.isRunning)
                        Text("The computer uses its own ChatGPT sign-in. The selected model stays the same; unavailable connections do not silently switch providers.").font(.footnote).foregroundStyle(.secondary)
                        Button("Check connection", systemImage: "arrow.clockwise") { Task { await check(connection) } }
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
            let (connection, token) = try await CompanionClient.pair(code, deviceName: "My iPhone")
            try CredentialStore.save(token, account: connection.credentialAccount)
            var next = model.settings; next.companion = connection; next.useComputer = true
            try model.saveSettings(next); manualCode = ""; AppFeedback.play(.saved)
            await check(connection)
        } catch { self.error = error.localizedDescription }
    }
    private func check(_ connection: CompanionConnection) async {
        do {
            let client = try CompanionClient(baseURL: connection.baseURL, fingerprint: connection.certificateSHA256, token: CredentialStore.read(account: connection.credentialAccount))
            let info = try await client.json("/v1/capabilities")
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
