import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var draft = ModelSettings()
    @State private var credential = ""
    @State private var saved = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Reasoning model") {
                    Picker("Use", selection: $draft.choice) { ForEach(ModelChoice.allCases) { choice in Text(choice.title).tag(choice) } }
                    switch draft.choice {
                    case .localMLX:
                        TextField("MLX vision model repository", text: $draft.localRepository).textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("Revision", text: $draft.localRevision).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Stepper("Response budget: \(draft.localResponseTokens) tokens", value: $draft.localResponseTokens, in: 512...8192, step: 512)
                        Toggle("Allow cellular model downloads", isOn: $draft.allowCellularDownloads)
                    case .openAI:
                        TextField("Model identifier", text: $draft.openAIModel).textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField("API key — saved only in Keychain", text: $credential).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Text("This build supports an OpenAI API key. Sign in with ChatGPT is a separate integration and is not implemented yet. API use may incur charges.").font(.footnote).foregroundStyle(.secondary)
                    case .compatibleServer:
                        TextField("Base URL ending in /v1", text: $draft.compatibleBaseURL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("Model identifier", text: $draft.compatibleModel).textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField("Server token, if required", text: $credential).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    Button("Save model settings") {
                        do { try model.saveSettings(draft, credential: credential); credential = ""; saved = true }
                        catch { model.errorMessage = error.localizedDescription }
                    }.disabled(model.isRunning || model.isDownloading)
                    if saved { Text("Saved").foregroundStyle(.secondary) }
                }
                Section("Downloaded model") {
                    Text(model.modelStatus)
                    Text("Save settings before downloading. Model weights can take several gigabytes. The current native baseline is Qwen3.5-4B; other MLX vision models still need device validation.").font(.footnote).foregroundStyle(.secondary)
                    if model.isDownloading {
                        ProgressView(value: model.downloadProgress)
                        Button("Stop download", role: .cancel) { model.stopDownload() }
                    } else {
                        Button("Download and load selected model") { model.downloadModel() }.disabled(model.isRunning || draft != model.settings)
                        Button("Unload from memory") { model.unloadModel() }.disabled(model.isRunning)
                    }
                }
                Section("Privacy") {
                    Text("Captures and conversations are stored in this app and excluded from device backups by default. Local chat does not download models automatically. Network use requires permission for the current conversation.").font(.footnote)
                    Button("Revoke this conversation’s network permission") { model.revokeNetworkConsent() }.disabled(model.isRunning)
                    Button("Remove saved credential for selected endpoint", role: .destructive) {
                        do { try model.clearCredential() } catch { model.errorMessage = error.localizedDescription }
                    }.disabled(model.isRunning || draft != model.settings)
                }
                Section("First native build") {
                    Text("Camera snapshots, OCR, saved depth, persistent conversations, and one read-only tool. Watch, TrueDepth, long-term memory search, code execution, and account sign-in are later increments.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .onAppear { draft = model.settings; saved = false }
            .onChange(of: draft) { _, _ in saved = false }
        }
    }
}
