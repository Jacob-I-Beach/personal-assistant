import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ModelSettings()
    @State private var credential = ""
    @State private var showSaved = false
    var body: some View {
        NavigationStack {
            Form {
                Section("ChatGPT") {
                    ForEach(model.accounts) { account in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(account.label).font(.subheadline)
                            if account.isConnected {
                                Button("Sign out", role: .destructive) { Task { await model.disconnectAccount(account) } }.disabled(model.isRunning)
                            } else { Button("Reconnect") { model.connectChatGPT(clientID: account.id) } }
                        }
                    }
                    Button("Continue with ChatGPT") { model.connectChatGPT() }.disabled(model.isConnecting || model.isRunning)
                    Link("Manage ChatGPT usage", destination: URL(string: "https://chatgpt.com/settings/usage")!)
                }
                Section("On-device models") {
                    Toggle("Allow cellular downloads", isOn: $draft.allowCellularDownloads)
                    Stepper("Response budget: \(draft.localResponseTokens)", value: $draft.localResponseTokens, in: 512...8192, step: 512)
                    Button("Release model memory") { model.unloadModel() }.disabled(model.isRunning)
                    Text("Downloads stay on disk when memory is released. The practical context and model size depend on device measurements.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Privacy and recovery") {
                    Toggle("Work only on this device", isOn: $draft.localOnly)
                    Text("Blocks connected models and account-model refreshes. Turn this off temporarily when downloading model files.").font(.footnote).foregroundStyle(.secondary)
                    Toggle("Include user data in device backups", isOn: $draft.includeInDeviceBackup)
                    Text("Conversations, captures, and files stay excluded until you enable this. Model weights are always excluded. Account credentials remain in this device's Keychain.").font(.footnote).foregroundStyle(.secondary)
                    Button("Revoke network access for this conversation") { model.revokeNetworkConsent() }.disabled(model.isRunning)
                }
                Section {
                    DisclosureGroup("Other connections") {
                        Picker("Connection", selection: $draft.choice) {
                            Text("Keep current model").tag(model.settings.choice)
                            if model.settings.choice != .openAI { Text("OpenAI API key").tag(ModelChoice.openAI) }
                            if model.settings.choice != .compatibleServer { Text("PC / compatible server").tag(ModelChoice.compatibleServer) }
                        }
                        if draft.choice == .openAI {
                            TextField("API model identifier", text: $draft.openAIModel).textInputAutocapitalization(.never).autocorrectionDisabled()
                            SecureField("OpenAI API key", text: $credential)
                            Text("API usage has separate billing from a ChatGPT subscription.").font(.footnote).foregroundStyle(.secondary)
                        } else if draft.choice == .compatibleServer {
                            TextField("Server address ending in /v1", text: $draft.compatibleBaseURL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                            TextField("Server model identifier", text: $draft.compatibleModel).textInputAutocapitalization(.never).autocorrectionDisabled()
                            SecureField("Server token, if needed", text: $credential)
                        }
                    }
                }
                Section("About") {
                    Text("Personal Assistant").font(.headline)
                    Text("A private workspace for your conversations, models, and useful work.").foregroundStyle(.secondary)
                    NavigationLink("Open-source acknowledgments") { AcknowledgmentsView() }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do { try model.saveSettings(draft, credential: credential); credential = ""; showSaved = true }
                        catch { model.errorMessage = error.localizedDescription }
                    }.disabled(model.isRunning)
                }
            }
            .onAppear { draft = model.settings }
            .onChange(of: model.settings.chatGPTAccountID) { _, _ in
                draft.chatGPTAccountID = model.settings.chatGPTAccountID
                draft.chatGPTModel = model.settings.chatGPTModel
                draft.choice = model.settings.choice
            }
            .alert("Settings saved", isPresented: $showSaved) { Button("Done") { dismiss() } }
        }
    }
}
private struct AcknowledgmentsView: View {
    var body: some View {
        List {
            Text("Built with Apple's platform frameworks, MLX Swift LM, Hugging Face, SQLite, QuickJS-NG, JOSESwift, and MarkdownUI.")
            ForEach(["QuickJS-License", "JOSESwift-License", "MarkdownUI-License"], id: \.self) { name in
                if let url = Bundle.main.url(forResource: name, withExtension: "txt"), let text = try? String(contentsOf: url, encoding: .utf8) {
                    NavigationLink(name.replacingOccurrences(of: "-License", with: "")) { ScrollView { Text(text).font(.caption).textSelection(.enabled).padding() }.navigationTitle("License") }
                }
            }
        }.navigationTitle("Acknowledgments")
    }
}
