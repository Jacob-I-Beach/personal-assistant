import AssistantCore
import SwiftUI

/// The daily chooser owns selection. Connection diagnostics and package
/// management live on their own surfaces, so they cannot crowd out choices.
struct ModelLibraryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var detail: LocalModelCatalogEntry?
    @State private var showAccount = false
    @State private var size: PresentationDetent = .medium
    private var localFirst: Bool { [.appleOnDevice, .localMLX].contains(model.settings.choice) }
    var body: some View {
        NavigationStack {
            List {
                Section { LocalRecoveryRow() }
                Section { ReadinessRow() }
                if localFirst { phoneModels; chatGPTModels } else { chatGPTModels; phoneModels }
                if model.appleCloud.isAvailable || model.settings.choice == .appleCloud {
                    Section("Apple cloud") {
                        ModelChoiceRow(title: model.appleCloud.title, subtitle: model.appleCloud.isAvailable ? "Private Cloud Compute" : "Not available in this installation", symbol: "cloud",
                            selected: model.settings.choice == .appleCloud, enabled: model.appleCloud.isAvailable && !model.isRunning) {
                            model.chooseApple(.privateCloud); dismiss()
                        }
                    }
                }
                Section {
                    NavigationLink {
                        ModelDownloadsView().onAppear { size = .large }
                    } label: { Label("Browse downloads", systemImage: "arrow.down.circle") }
                }
                if let entry = model.catalog.first(where: { $0.id == model.downloadingModelID }) {
                    Section { ModelDownloadProgress(entry: entry) }
                }
            }
            .navigationTitle("Models").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await model.refreshDownloads(); await model.refreshAccounts() }
            .sheet(item: $detail) { LocalModelDetailsView(entry: $0) }
            .sheet(isPresented: $showAccount) { ModelAccountDetailsView() }
        }
        .presentationDetents([.medium, .large], selection: $size).presentationDragIndicator(.visible)
    }
    private var phoneModels: some View {
        Section("On this iPhone") {
            ModelChoiceRow(title: model.appleDevice.title, subtitle: model.appleDevice.isAvailable ? "Built in" : "Not available on this device", symbol: "sparkles",
                selected: model.settings.choice == .appleOnDevice, enabled: model.appleDevice.isAvailable && !model.isRunning) {
                model.chooseApple(.device); dismiss()
            }
            ForEach(model.catalog.filter { model.downloadedModelIDs.contains($0.id) }) { entry in
                HStack(spacing: 4) {
                    ModelChoiceRow(title: entry.name, subtitle: "Downloaded", symbol: "cpu",
                        selected: model.settings.choice == .localMLX && model.settings.localRepository == entry.id, enabled: !model.isRunning) {
                        model.chooseLocal(entry); dismiss()
                    }
                    Button { detail = entry } label: { Image(systemName: "info.circle").frame(width: 44, height: 44) }
                        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Details for " + entry.name)
                }
            }
        }
    }
    private var chatGPTModels: some View {
        Section {
            if model.usesComputerChatGPT || model.accounts.contains(where: \.isConnected) {
                ForEach(model.chatGPTModels) { entry in
                    ModelChoiceRow(title: entry.displayName, subtitle: model.modelCatalog.phase == .ready ? "ChatGPT plan" : "Saved model", symbol: "sparkles",
                        selected: model.settings.choice == .chatGPT && model.settings.chatGPTModel == entry.id, enabled: !model.isRunning && !model.settings.localOnly) {
                        model.chooseChatGPTModel(entry); dismiss()
                    }
                }
                if !model.settings.chatGPTModel.isEmpty, !model.chatGPTModels.contains(where: { $0.id == model.settings.chatGPTModel }) {
                    ModelChoiceRow(title: ChatGPTModel.displayTitle(for: model.settings.chatGPTModel, catalog: []), subtitle: "Last used", symbol: "sparkles",
                        selected: model.settings.choice == .chatGPT, enabled: !model.isRunning && !model.settings.localOnly) {
                        model.chooseSavedChatGPTModel(); dismiss()
                    }
                }
                if model.chatGPTModels.isEmpty && model.settings.chatGPTModel.isEmpty {
                    Label(model.modelCatalog.phase == .refreshing ? "Loading models…" : "Models unavailable", systemImage: "cloud")
                        .foregroundStyle(.secondary)
                }
            } else {
                Button { model.connectChatGPT() } label: { Label("Continue with ChatGPT", systemImage: "person.crop.circle") }
                    .disabled(model.isConnecting || model.isRunning || model.settings.localOnly)
            }
        } header: {
            HStack {
                Text("ChatGPT")
                Spacer()
                Button("Manage") { showAccount = true }.textCase(nil).font(.caption)
                    .accessibilityIdentifier("model-account-details")
            }
        } footer: {
            if model.settings.localOnly { Text("On-device mode is enabled.") }
            else if model.modelCatalog.phase == .unavailable || model.modelCatalog.phase == .stale {
                Text("Connection needs attention. Manage your account for details.")
                    .accessibilityIdentifier("model-connection-summary")
            }
        }
    }
}

struct ModelChoiceRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    let selected: Bool
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 18, weight: .medium))
                    .frame(width: 36, height: 36).background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.body.weight(.medium))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if selected { Image(systemName: "checkmark").font(.body.weight(.semibold)) }
            }.foregroundStyle(.primary).padding(.vertical, 4).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.5)
            .accessibilityLabel(title).accessibilityValue(selected ? "Selected" : subtitle)
    }
}
