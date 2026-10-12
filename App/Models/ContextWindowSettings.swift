import AssistantCore
import SwiftUI
import os

extension ModelSettings {
    var contextModelID: String {
        switch choice {
        case .chatGPT: chatGPTModel
        case .openAI: openAIModel
        case .compatibleServer: compatibleModel
        default: ""
        }
    }
    var contextPreferenceKey: String {
        // A transport change does not discard the user's per-model preference.
        let owner = choice == .chatGPT ? chatGPTAccountID.map { "chatgpt-account:" + $0 } : networkDestination
        return (owner ?? choice.rawValue) + ":" + contextModelID
    }
}

extension AppModel {
    func localContextBudget(memoryGiB: Int? = nil, tokens: Int? = nil) -> LocalInferenceBudget {
        LocalInferenceBudget(weightBytes: catalog.first { $0.id == settings.localRepository }?.weightBytes ?? 0,
            availableBytes: Int64(os_proc_available_memory()), residentBytes: localBackendResidentBytes,
            requestedMemoryGiB: memoryGiB ?? settings.localMemoryGiB, requestedContextTokens: tokens ?? settings.localContextTokens,
            responseTokens: settings.localResponseTokens, supportsEfficientKV: settings.localRepository.contains("Qwen3.5-4B"))
    }
    func contextBudget(for selection: ModelSettings) -> ModelContextBudget? {
        guard [.chatGPT, .openAI, .compatibleServer].contains(selection.choice) else { return nil }
        let entry = selection.choice == .chatGPT ? chatGPTModels.first { $0.id == selection.chatGPTModel } : nil
        return ModelContextBudget(model: selection.choice == .compatibleServer ? "" : selection.contextModelID,
            advertisedWindow: entry?.contextWindow, advertisedMaximumWindow: entry?.maximumContextWindow,
            requestedInputTokens: selection.contextTokensByModel[selection.contextPreferenceKey])
    }
}

struct ContextWindowView: View {
    var body: some View { ReasoningEffortView(focusContext: true) }
}
