import SwiftUI
import UniformTypeIdentifiers
import os

struct ModelLibraryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var importEntry: LocalModelCatalogEntry?
    @State private var showImport = false
    @State private var availableMemory: UInt64 = 0
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Allow cellular downloads", isOn: Binding(get: { model.settings.allowCellularDownloads }, set: { enabled in
                        var settings = model.settings; settings.allowCellularDownloads = enabled
                        do { try model.saveSettings(settings) } catch { model.errorMessage = error.localizedDescription }
                    })).disabled(model.isDownloading || model.isRunning)
                    Text("Downloads use Wi-Fi unless enabled here. Tap Download again after an interruption to reuse completed files and resume supported transfers.").font(.caption).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your assistant. Your choice.").font(.title3.weight(.semibold))
                        Text("Keep the conversation, tools, and files as you change models.").font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                }
                Section("ChatGPT") {
                    if model.settings.useComputer, let connection = model.settings.companion {
                        Label(model.chatGPTAccountLabel, systemImage: "person.crop.circle")
                            .accessibilityIdentifier("connected-chatgpt-account")
                        Text(model.computerAccountDetail).font(.subheadline).foregroundStyle(.secondary)
                        Text("The account connected on \(connection.name) runs these models. Your task continues there when this app closes.").font(.caption).foregroundStyle(.secondary)
                        ForEach(model.chatGPTModels) { entry in
                            Button { model.chooseChatGPTModel(entry) } label: {
                                HStack { Text(entry.displayName).foregroundStyle(.primary); Spacer(); if model.settings.choice == .chatGPT && model.settings.chatGPTModel == entry.id { Image(systemName: "checkmark") } }
                            }.disabled(model.isRunning)
                        }
                        Button("Refresh models") { Task { await model.refreshAccounts() } }
                        NavigationLink("Account & connection") { ComputerConnectionView() }
                    } else if model.accounts.contains(where: \.isConnected) {
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
                    ForEach(model.usesComputerChatGPT ? [] : model.accounts.filter { !$0.isConnected }) { account in
                        Button(account.label) { model.connectChatGPT(clientID: account.id) }.disabled(model.isConnecting || model.isRunning)
                    }
                }
                Section("Apple intelligence") {
                    appleRow(model.appleDevice, location: .device)
                    appleRow(model.appleCloud, location: .privateCloud)
                }
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("This iPhone").font(.headline)
                        Text("\(ByteCountFormatter.string(fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory), countStyle: .memory)) physical memory · " + (availableMemory == 0 ? "Available memory not reported" : "\(ByteCountFormatter.string(fromByteCount: Int64(availableMemory), countStyle: .memory)) currently available to this app")).font(.caption).foregroundStyle(.secondary)
                        Text("Memory availability changes as iOS manages other work. Estimates below include working overhead, but context and images can increase it.").font(.caption2).foregroundStyle(.secondary)
                    }.padding(.vertical, 5)
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
                            Label("Estimated working memory: \(entry.memoryEstimate)", systemImage: "memorychip").font(.caption).foregroundStyle(.secondary)
                            if let low = entry.estimatedMemoryLowBytes, availableMemory > 0 {
                                Text(UInt64(low) > availableMemory ? "Above current memory headroom · experimental fit" : "Within the estimate at this moment · speed unmeasured").font(.caption2).foregroundStyle(.secondary)
                            }
                            if let moe = entry.mixtureOfExperts { Text("MoE · \(moe). All expert weights count toward memory.").font(.caption2).foregroundStyle(.secondary) }
                            if let source = entry.sourceURL { Link("Model card & pinned package", destination: source).font(.caption) }
                            if model.downloadingModelID == entry.id {
                                ProgressView(value: model.downloadProgress)
                                Text(ByteCountFormatter.string(fromByteCount: Int64(Double(entry.downloadBytes) * model.downloadProgress), countStyle: .file) + " of " + entry.downloadSize)
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                HStack { Text(model.modelStatus).font(.caption); Spacer(); Button("Stop", role: .cancel) { model.stopDownload() }.font(.subheadline) }
                            } else if model.downloadedModelIDs.contains(entry.id) {
                                Button { model.chooseLocal(entry) } label: { Text("Use \(entry.name)").foregroundStyle(Color(uiColor: .systemBackground)) }.buttonStyle(.borderedProminent).tint(Color.primary).disabled(model.isRunning)
                            } else {
                                HStack {
                                    Button("Download") { model.downloadModel(entry) }.buttonStyle(.bordered).disabled(model.settings.localOnly)
                                    Button("Import from Files") { importEntry = entry; showImport = true }.font(.subheadline).buttonStyle(.borderless)
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
            .task { availableMemory = UInt64(os_proc_available_memory()); await model.refreshDownloads(); await model.refreshAccounts() }
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
