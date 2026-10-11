import AssistantCore
import SwiftUI

extension ModelSettings {
    var contextModelID: String {
        switch choice {
        case .chatGPT: chatGPTModel
        case .openAI: openAIModel
        case .compatibleServer: compatibleModel
        default: ""
        }
    }
    var contextPreferenceKey: String { (networkDestination ?? choice.rawValue) + ":" + contextModelID }
}

extension AppModel {
    func contextBudget(for selection: ModelSettings) -> ModelContextBudget? {
        guard [.chatGPT, .openAI, .compatibleServer].contains(selection.choice) else { return nil }
        let advertised = selection.choice == .chatGPT ? chatGPTModels.first { $0.id == selection.chatGPTModel }?.contextWindow : nil
        return ModelContextBudget(model: selection.choice == .compatibleServer ? "" : selection.contextModelID,
            advertisedWindow: advertised, requestedInputTokens: selection.contextTokensByModel[selection.contextPreferenceKey])
    }
}

struct ContextWindowView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Int?
    private var plan: ModelContextBudget? { model.contextBudget(for: model.settings) }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("How much of the conversation to work with").font(.title3.weight(.semibold))
                    Text("A larger context keeps more earlier messages and tool results available in each request. Your complete conversation stays saved at every setting.").font(.subheadline).foregroundStyle(.secondary)
                }
                if let plan {
                    Section(model.modelTitle) {
                        choice("Automatic", value: nil)
                        ForEach(plan.presets, id: \.self) { tokens in choice(tokens.formatted() + " tokens", value: tokens) }
                    }
                    Section("Model limit") {
                        LabeledContent("Total context", value: plan.modelWindow.formatted() + " tokens")
                        LabeledContent("Reserved for the reply", value: plan.outputReserve.formatted() + " tokens")
                        Text(plan.limitSource).font(.caption).foregroundStyle(.secondary)
                        Text("The working budget uses an approximate text-to-token estimate; images, files and reasoning also use context. The service enforces the final limit. Larger requests can take longer and use more of your account allowance.").font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    Text("This on-device model manages context through its runtime and available memory. Large cloud context sizes do not apply to it.").foregroundStyle(.secondary)
                }
            }.navigationTitle("Working context").navigationBarTitleDisplayMode(.inline)
                .onAppear { selected = model.settings.contextTokensByModel[model.settings.contextPreferenceKey] }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") {
                        var next = model.settings; next.contextTokensByModel[next.contextPreferenceKey] = selected
                        do { try model.saveSettings(next); AppFeedback.play(.saved); dismiss() }
                        catch { model.errorMessage = error.localizedDescription }
                    }.disabled(model.isRunning || plan == nil) }
                }
        }
    }
    private func choice(_ title: String, value: Int?) -> some View {
        Button { selected = value; AppFeedback.play(.selection) } label: {
            HStack { Text(title); Spacer(); if selected == value { Image(systemName: "checkmark") } }.contentShape(Rectangle())
        }.buttonStyle(QuietPressStyle()).foregroundStyle(.primary)
    }
}
