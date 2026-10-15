import SwiftUI

struct ModelAccountDetailsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    Label(model.chatGPTAccountLabel, systemImage: "person.crop.circle")
                        .accessibilityIdentifier("connected-chatgpt-account")
                    if model.usesComputerChatGPT {
                        Text(model.computerAccountDetail).font(.subheadline).foregroundStyle(.secondary)
                        NavigationLink("Computer connection") { ComputerConnectionView() }
                    } else {
                        ForEach(model.accounts.filter(\.isConnected)) { account in
                            Button(account.label) { Task { await model.switchAccount(account) } }.disabled(model.isRunning)
                        }
                        Button("Add an account") { model.connectChatGPT() }.disabled(model.isConnecting || model.isRunning || model.settings.localOnly)
                        if let id = model.settings.chatGPTAccountID {
                            Button("Reconnect this account") { model.connectChatGPT(clientID: id) }.disabled(model.isConnecting || model.isRunning || model.settings.localOnly)
                        }
                    }
                }
                Section("Model availability") {
                    if model.modelCatalog.phase == .refreshing { ProgressView("Refreshing model choices") }
                    Text(model.modelCatalog.detail).font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityIdentifier("model-catalog-status")
                    Button("Refresh models") { Task { await model.refreshAccounts(force: true) } }
                        .disabled(model.modelCatalog.phase == .refreshing || model.settings.localOnly)
                    Text("A saved sign-in and model-service availability are checked separately. Saved choices remain available when a refresh fails.").font(.caption).foregroundStyle(.secondary)
                }
                if model.usesComputerChatGPT {
                    Section("Mobile fallback") {
                        Label(model.mobileChatGPTConnected ? "ChatGPT connected on this iPhone" : "Connect ChatGPT on this iPhone", systemImage: "iphone")
                        Text("New requests use this separate sign-in when the computer is off or unreachable. Accepted computer tasks stay on the computer and sync when it returns. Mobile replies may need Continue reply after iOS suspends the app.").font(.caption).foregroundStyle(.secondary)
                        Button(model.mobileChatGPTConnected ? "Reconnect mobile ChatGPT" : "Connect mobile ChatGPT") { model.connectChatGPT(clientID: model.settings.chatGPTAccountID) }
                            .disabled(model.isConnecting || model.isRunning || model.settings.localOnly)
                    }
                }
                if !model.appleCloud.isAvailable {
                    Section("Other connections") {
                        LabeledContent("Apple Private Cloud Compute", value: "Not configured")
                        Text(model.appleCloud.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Account & connection").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
