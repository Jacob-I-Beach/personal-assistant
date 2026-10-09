import SwiftUI
import UniformTypeIdentifiers

struct ModelLibraryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var importEntry: LocalModelCatalogEntry?
    @State private var showImport = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your assistant. Your choice.").font(.title3.weight(.semibold))
                        Text("Keep the conversation, tools, and files as you change models.").font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                }
                Section("ChatGPT") {
                    if model.accounts.contains(where: \.isConnected) {
                        Menu {
                            ForEach(model.accounts.filter(\.isConnected)) { account in
                                Button(account.label) { Task { await model.switchAccount(account) } }
                            }
                            Button("Add another account") { model.connectChatGPT() }
                            if let id = model.settings.chatGPTAccountID { Button("Reconnect selected account") { model.connectChatGPT(clientID: id) } }
                        } label: {
                            Label(model.accounts.first { $0.id == model.settings.chatGPTAccountID }?.label ?? "Choose an account", systemImage: "person.crop.circle")
                                .font(.subheadline)
                        }.disabled(model.isRunning)
                        ForEach(model.chatGPTModels) { entry in
                            Button { model.chooseChatGPTModel(entry) } label: {
                                HStack { Text(entry.displayName).foregroundStyle(.primary); Spacer(); if model.settings.choice == .chatGPT && model.settings.chatGPTModel == entry.id { Image(systemName: "checkmark").fontWeight(.semibold) } }
                            }.disabled(model.isRunning)
                        }
                        if model.chatGPTModels.isEmpty {
                            Button("Reload account models") { Task { await model.refreshAccounts() } }
                        }
                        Text("Uses your ChatGPT plan and its app usage limits.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button { model.connectChatGPT() } label: {
                            HStack { Text("Continue with ChatGPT").fontWeight(.semibold); Spacer(); if model.isConnecting { ProgressView() } else { Image(systemName: "arrow.right") } }
                        }.disabled(model.isConnecting || model.isRunning)
                        Text("Sign in through OpenAI. Your password stays in the authentication browser.").font(.caption).foregroundStyle(.secondary)
                    }
                    if model.isConnecting { Button("Cancel sign-in", role: .cancel) { model.cancelConnection() } }
                    ForEach(model.accounts.filter { !$0.isConnected }) { account in
                        Button(account.label) { model.connectChatGPT(clientID: account.id) }.disabled(model.isConnecting || model.isRunning)
                    }
                }
                Section("Apple intelligence") {
                    appleRow(model.appleDevice, location: .device)
                    appleRow(model.appleCloud, location: .privateCloud)
                }
                Section {
                    ForEach(model.catalog) { entry in
                        VStack(alignment: .leading, spacing: 11) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(entry.name).font(.headline)
                                Spacer()
                                if model.settings.choice == .localMLX && model.settings.localRepository == entry.id && model.downloadedModelIDs.contains(entry.id) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
                            }
                            Text(entry.summary).font(.subheadline).foregroundStyle(.secondary)
                            HStack(spacing: 12) {
                                Label(entry.downloadSize, systemImage: "arrow.down.circle")
                                if entry.supportsVision { Label("Images", systemImage: "photo") }
                                Text(entry.format)
                            }.font(.caption).foregroundStyle(.secondary)
                            if model.downloadingModelID == entry.id {
                                ProgressView(value: model.downloadProgress)
                                HStack { Text(model.modelStatus).font(.caption); Spacer(); Button("Stop", role: .cancel) { model.stopDownload() }.font(.subheadline) }
                            } else if model.downloadedModelIDs.contains(entry.id) {
                                Button("Use \(entry.name)") { model.chooseLocal(entry) }.buttonStyle(.borderedProminent).disabled(model.isRunning)
                            } else {
                                HStack {
                                    Button("Download") { model.downloadModel(entry) }.buttonStyle(.bordered).disabled(model.settings.localOnly)
                                    Button("Import from Files") { importEntry = entry; showImport = true }.font(.subheadline)
                                }.disabled(model.isDownloading || (model.isRunning && model.settings.choice == .localMLX))
                            }
                            Text(entry.validation).font(.caption2).foregroundStyle(.secondary)
                        }.padding(.vertical, 9)
                    }
                } header: { Text("Download to this iPhone") } footer: {
                    Text("Download size is storage, not working memory. Larger models will be measured on your phone before we label them recommended. You can keep using ChatGPT during a download.")
                }
            }
            .navigationTitle("Models")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await model.refreshDownloads() }
            .fileImporter(isPresented: $showImport, allowedContentTypes: [.folder]) { result in
                guard let entry = importEntry else { return }
                switch result {
                case .success(let folder): model.importModel(entry, folder: folder)
                case .failure(let error): model.errorMessage = error.localizedDescription
                }
            }
        }.presentationDragIndicator(.visible)
    }
    private func appleRow(_ readiness: AppleModelReadiness, location: AppleModelBackend.Location) -> some View {
        Button { model.chooseApple(location) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(readiness.title).foregroundStyle(.primary)
                    Text(readiness.detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if (location == .device && model.settings.choice == .appleOnDevice) || (location == .privateCloud && model.settings.choice == .appleCloud) { Image(systemName: "checkmark") }
            }
        }.disabled(!readiness.isAvailable || model.isRunning)
    }
}
