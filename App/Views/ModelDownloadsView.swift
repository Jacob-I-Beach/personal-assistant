import AssistantCore
import SwiftUI
import UniformTypeIdentifiers

struct ModelDownloadsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var detail: LocalModelCatalogEntry?
    var body: some View {
        List {
            Section {
                ForEach(model.catalog) { entry in
                    Button { detail = entry } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "cpu").font(.title3).frame(width: 32)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.name).font(.body.weight(.medium)).foregroundStyle(.primary)
                                Text(model.downloadedModelIDs.contains(entry.id) ? "Downloaded" : entry.downloadSize + " · " + entry.format)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: model.downloadedModelIDs.contains(entry.id) ? "checkmark.circle" : "chevron.right").font(.subheadline).foregroundStyle(.secondary)
                        }.padding(.vertical, 5).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(entry.name + " details")
                }
            } footer: { Text("Models stay on this iPhone after downloading. Open a model for its capabilities and storage details.") }
            Section("Downloads") {
                Toggle("Allow cellular downloads", isOn: Binding(get: { model.settings.allowCellularDownloads }, set: { enabled in
                    var next = model.settings; next.allowCellularDownloads = enabled
                    do { try model.saveSettings(next) } catch { model.errorMessage = error.localizedDescription }
                })).disabled(model.isDownloading || model.isRunning)
            }
        }
        .navigationTitle("Downloads").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $detail) { LocalModelDetailsView(entry: $0) }
    }
}

struct ModelDownloadProgress: View {
    @EnvironmentObject private var model: AppModel
    let entry: LocalModelCatalogEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(entry.name).font(.subheadline.weight(.medium))
            ProgressView(value: model.downloadProgress)
            Text(model.modelStatus).font(.caption).foregroundStyle(.secondary)
            HStack {
                Text(ByteCountFormatter.string(fromByteCount: Int64(Double(entry.downloadBytes) * model.downloadProgress), countStyle: .file) + " of " + entry.downloadSize)
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Button("Stop", role: .cancel) { model.stopDownload() }.font(.subheadline)
            }
        }.padding(.vertical, 5)
    }
}

struct LocalModelDetailsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let entry: LocalModelCatalogEntry
    @State private var importFolder = false
    @State private var showResponseSettings = false
    private var selected: Bool { model.settings.choice == .localMLX && model.settings.localRepository == entry.id }
    private var downloaded: Bool { model.downloadedModelIDs.contains(entry.id) }
    private var plan: LocalInferenceBudget { model.localBudget(for: entry) }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(entry.name).font(.title2.weight(.semibold))
                        Text(entry.summary).font(.subheadline).foregroundStyle(.secondary)
                        Text(entry.format + " · " + entry.downloadSize).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 6)
                    if model.downloadingModelID == entry.id { ModelDownloadProgress(entry: entry) }
                    else if downloaded {
                        Button(selected ? "Selected for this chat" : "Use this model", systemImage: selected ? "checkmark" : "arrow.right") {
                            model.chooseLocal(entry); dismiss()
                        }.disabled(selected || model.isRunning)
                    } else {
                        Button("Download model", systemImage: "arrow.down.circle") { model.downloadModel(entry) }
                            .disabled(model.settings.localOnly || model.isDownloading || model.isRunning)
                        Button("Import matching files", systemImage: "folder") { importFolder = true }.disabled(model.isDownloading || model.isRunning)
                    }
                }
                Section("Working context") {
                    LabeledContent("Estimated text context", value: plan.fits ? plan.selectedContextTokens.formatted() + " tokens" : "More memory needed")
                        .accessibilityElement(children: .ignore).accessibilityLabel("Estimated text context")
                        .accessibilityValue(plan.fits ? plan.selectedContextTokens.formatted() + " tokens" : "More memory needed")
                        .accessibilityIdentifier("local-context-estimate")
                    Text(plan.fits ? "The runtime checks again after loading and adapts to actual memory headroom. Your full chat remains saved." : "The current allowance cannot fit this runtime. The download stays on the phone; this is a memory-readiness issue.")
                        .font(.caption).foregroundStyle(.secondary)
                    if selected { Button("Response settings", systemImage: "brain") { showResponseSettings = true } }
                    if entry.textWeightBytes != nil {
                        Text("Text uses the same language weights without the vision tower. Image requests load the larger runtime only when it fits.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    DisclosureGroup("Memory and storage") {
                        LabeledContent("iOS headroom", value: bytes(model.localMemoryHeadroom))
                        LabeledContent("Planned working budget", value: bytes(plan.workingBytes))
                        LabeledContent("Language weights", value: bytes(entry.textWeightBytes ?? entry.weightBytes ?? 0))
                        if let text = entry.textWeightBytes { LabeledContent("Text-runtime cache", value: bytes(text)); Text("Prepared from the existing download on first use. No additional model download is needed.").font(.caption).foregroundStyle(.secondary) }
                        Text("The memory ceiling does not change iOS's allowance. Higher limits require a supported device and matching signing capabilities.").font(.caption).foregroundStyle(.secondary)
                        if selected, model.localBackendResidentBytes > 0 {
                            Button("Release loaded memory") { model.unloadModel() }.disabled(model.isRunning)
                        }
                    }
                    if let source = entry.sourceURL { Link("Model information", destination: source) }
                }
            }
            .navigationTitle("Model details").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showResponseSettings) { ReasoningEffortView(focusContext: true) }
            .fileImporter(isPresented: $importFolder, allowedContentTypes: [.folder]) { result in
                switch result {
                case .success(let url): model.importModel(entry, folder: url)
                case .failure(let error): model.errorMessage = error.localizedDescription
                }
            }
        }
    }
    private func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .memory) }
}
