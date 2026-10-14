import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ModelSettings()
    @State private var credential = ""
    @State private var localError: String?
    @State private var connectionNotice: String?
    @State private var discardConnection = false
    @State private var initialConnection = ModelSettings()
    @State private var showContext = false
    var body: some View {
        NavigationStack {
            Form {
                Section { NavigationLink { DeviceAccessView() } label: { Label("Tools & device", systemImage: "iphone") } }
                Section("ChatGPT") {
                    if model.usesComputerChatGPT {
                        Label(model.chatGPTAccountLabel, systemImage: "person.crop.circle")
                        Text(model.computerAccountDetail).font(.footnote).foregroundStyle(.secondary)
                        NavigationLink("Account & connection") { ComputerConnectionView() }
                    } else {
                    ForEach(model.accounts) { account in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(account.label).font(.subheadline)
                            if account.isConnected {
                                Button(model.isManagingAccount ? "Signing out…" : "Sign out", role: .destructive) { Task { await model.disconnectAccount(account) } }.disabled(model.isRunning || model.isManagingAccount || model.isConnecting)
                            } else { Button("Reconnect") { model.connectChatGPT(clientID: account.id) } }
                        }
                    }
                    Button(model.accounts.contains(where: \.isConnected) ? "Add another ChatGPT account" : "Continue with ChatGPT") { model.connectChatGPT() }.disabled(model.isConnecting || model.isRunning)
                    }
                    Link("Manage ChatGPT usage", destination: URL(string: "https://chatgpt.com/settings/usage")!)
                    Toggle("Allow web search with ChatGPT", isOn: preference(\.chatGPTWebSearch)).disabled(model.isRunning)
                    Text("Lets supported account models search the web and return source links. Availability follows the selected model and your account's policy. This does not grant browser control or network access to code.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("On-device models") {
                    Toggle("Allow cellular downloads", isOn: preference(\.allowCellularDownloads)).disabled(model.isRunning)
                    Stepper("Response budget: \(model.settings.localResponseTokens)", value: Binding(get: { model.settings.localResponseTokens }, set: { value in
                        do { try model.updatePreference(\.localResponseTokens, to: value); localError = nil } catch { localError = error.localizedDescription }
                    }), in: 512...8192, step: 512).disabled(model.isRunning)
                    Button("Unload from memory") { model.unloadModel() }.disabled(model.isRunning)
                    Text("Downloads stay on disk when memory is released. The practical context and model size depend on device measurements.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Privacy and recovery") {
                    Toggle("Confirm each new connected chat", isOn: preference(\.confirmNewConnectedChats)).disabled(model.isRunning)
                    Text("When off, Send uses the model you selected without another pop-up. Health sharing still has a separate review.").font(.footnote).foregroundStyle(.secondary)
                    Toggle("Allow iPhone background time", isOn: preference(\.continueInBackground)).disabled(model.isRunning)
                    Text("Apple and direct connected replies can use the background time iOS grants. Downloaded models pause when you leave the app." + (model.usesComputerChatGPT ? " Accepted ChatGPT tasks keep working on your computer independently of this setting; keep the computer awake and online." : " Stop a reply from its chat.")).font(.footnote).foregroundStyle(.secondary)
                    if TaskPresentationPolicy.isEnabled {
                        Toggle("Notify when a task needs attention", isOn: preference(\.taskNotifications)).disabled(model.isRunning)
                        Text("Receive a notice for reviews, completed replies, or saved work that needs attention. Tapping opens its chat.").font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text("Notifications and Live Activities are paused in this build. Questions and task status remain available in chat.").font(.footnote).foregroundStyle(.secondary)
                    }
                    Toggle("Automatic memory", isOn: preference(\.automaticMemory)).disabled(model.isRunning)
                    Text("Remember useful things you share and keep them current. Inferences stay tentative. Inspect changes and undo them in Library → Saved memory.").font(.footnote).foregroundStyle(.secondary)
                    Toggle("Allow workspace search", isOn: preference(\.workspaceSearchEnabled)).disabled(model.isRunning)
                    Text("Lets the selected model search other chats in this app and files you marked for workspace access. Connected models cannot search archived, on-device-only, or Health chats. This does not import your history from the ChatGPT app.").font(.footnote).foregroundStyle(.secondary)
                    Toggle("Allow assistant Health reads", isOn: preference(\.healthToolsEnabled)).disabled(model.isRunning).disabled(!HealthOverviewService.isEnabledInThisBuild)
                    Text(HealthOverviewService.isEnabledInThisBuild ? "Controls relevant reads of your selected Health data. Choose the types in Connections → Health → Connected data. Existing conversation records are kept until you remove them." : HealthOverviewService.signingMessage).font(.footnote).foregroundStyle(.secondary)
                    Toggle("Work only on this device", isOn: preference(\.localOnly)).disabled(model.isRunning)
                    Text("Blocks connected models and account-model refreshes. Turn this off temporarily when downloading model files.").font(.footnote).foregroundStyle(.secondary)
                    Toggle("Include user data in device backups", isOn: preference(\.includeInDeviceBackup)).disabled(model.isRunning).disabled(model.libraryContainsHealthData)
                    Text(model.libraryContainsHealthData ? "This library contains Health-derived information and stays excluded from device backups. Export selected items when needed." : "Conversations, memories, captures, and files stay excluded until you enable this. Model weights are always excluded. Account credentials remain in this device's Keychain.").font(.footnote).foregroundStyle(.secondary)
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
                        Button("Apply connection") {
                            var next = model.settings
                            next.choice = draft.choice; next.openAIModel = draft.openAIModel
                            next.compatibleBaseURL = draft.compatibleBaseURL; next.compatibleModel = draft.compatibleModel
                            do {
                                try model.saveSettings(next, credential: credential); credential = ""; initialConnection = model.settings; draft = model.settings
                                connectionNotice = "Connection settings applied."; localError = nil
                            } catch { localError = error.localizedDescription }
                        }.disabled(model.isRunning || !connectionIsDirty)
                        if let connectionNotice { Text(connectionNotice).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                Section("Feedback & voice") {
                    Toggle("Gentle haptics", isOn: preference(\.hapticsEnabled)).disabled(model.isRunning)
                    Text("Quiet feedback for selections, sending, copying and replies. A soft three-tap pattern means the assistant needs your answer.").font(.footnote).foregroundStyle(.secondary)
                    Toggle("Read completed responses aloud", isOn: preference(\.speakReplies)).disabled(model.isRunning)
                    Text("You can also play an individual answer from its speaker button. Voice input uses on-device transcription when available.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Conversations") {
                    Button("Home context", systemImage: "sun.max") { showContext = true }
                    Toggle("Automatic chat titles", isOn: preference(\.automaticChatTitles)).disabled(model.isRunning)
                    Text("Uses the selected model to name new chats after the first answer. Names you enter yourself are kept.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("About") {
                    Text("Personal Assistant").font(.headline)
                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") · Build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—")").font(.caption).foregroundStyle(.secondary)
                    Text("A private workspace for your conversations, models, and useful work.").foregroundStyle(.secondary)
                    NavigationLink("Open-source acknowledgments") { AcknowledgmentsView() }
                }
            }
            .navigationTitle("Settings")
            .safeAreaInset(edge: .bottom) {
                if let localError { Label(localError, systemImage: "exclamationmark.circle").font(.subheadline).frame(maxWidth: .infinity, alignment: .leading).padding(16).background(.bar).accessibilityIdentifier("settings-save-error") }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { if connectionIsDirty { discardConnection = true } else { dismiss() } } }
            }
            .onAppear { draft = model.settings; initialConnection = model.settings }
            .task { await model.refreshAccounts() }
            .onChange(of: model.settings.chatGPTAccountID) { _, _ in
                if !connectionIsDirty { draft = model.settings; initialConnection = model.settings }
            }
            .sheet(isPresented: $showContext, onDismiss: {
                draft.locationContextEnabled = model.settings.locationContextEnabled
                draft.weatherFollowsLocation = model.settings.weatherFollowsLocation
                draft.weatherPlace = model.settings.weatherPlace
            }) { HomeContextSettingsView() }
            .onChange(of: model.libraryContainsHealthData) { _, contains in if contains { draft.includeInDeviceBackup = false } }
            .interactiveDismissDisabled(connectionIsDirty)
            .confirmationDialog("Discard connection changes?", isPresented: $discardConnection, titleVisibility: .visible) {
                Button("Discard connection changes", role: .destructive) { credential = ""; dismiss() }
                Button("Keep editing", role: .cancel) { }
            } message: { Text("Ordinary preferences are already saved. Only the unapplied connection fields will be discarded.") }
        }
    }
    private func preference(_ key: WritableKeyPath<ModelSettings, Bool>) -> Binding<Bool> {
        Binding(get: { model.settings[keyPath: key] }, set: { value in
            guard model.settings[keyPath: key] != value else { return }
            do { try model.updatePreference(key, to: value); localError = nil; AppFeedback.play(.selection) }
            catch { localError = error.localizedDescription }
        })
    }
    private var connectionIsDirty: Bool {
        !credential.isEmpty || draft.choice != initialConnection.choice || draft.openAIModel != initialConnection.openAIModel
        || draft.compatibleBaseURL != initialConnection.compatibleBaseURL || draft.compatibleModel != initialConnection.compatibleModel
    }
}
private struct AcknowledgmentsView: View {
    var body: some View {
        List {
            Text("Built with Apple's platform frameworks, MLX Swift LM, Hugging Face, SQLite, QuickJS-NG, JOSESwift, Textual, SwiftUIMath, MarkdownUI, and ZIPFoundation.")
            ForEach(["QuickJS-License", "JOSESwift-License", "MarkdownUI-License", "ZIPFoundation-License", "Textual-License", "SwiftUIMath-License", "ConcurrencyExtras-License", "Prism-License"], id: \.self) { name in
                if let url = Bundle.main.url(forResource: name, withExtension: "txt"), let text = try? String(contentsOf: url, encoding: .utf8) {
                    NavigationLink(name.replacingOccurrences(of: "-License", with: "")) { ScrollView { Text(text).font(.caption).textSelection(.enabled).padding() }.navigationTitle("License") }
                }
            }
        }.navigationTitle("Acknowledgments")
    }
}
