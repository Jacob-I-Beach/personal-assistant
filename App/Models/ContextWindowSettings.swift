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
    var localMemoryHeadroom: Int64 {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-qwen-memory-granted") { return 6 * 1_073_741_824 }
        if ProcessInfo.processInfo.arguments.contains("--ui-qwen-memory") { return Int64(3.05 * 1_073_741_824) }
        #endif
        return Int64(os_proc_available_memory())
    }
    func localContextBudget() -> LocalInferenceBudget { localContextBudget(memoryGiB: settings.localMemoryGiB, tokens: settings.localContextTokens) }
    func localContextBudget(memoryGiB: Int, tokens: Int?) -> LocalInferenceBudget {
        if let prepared = localRuntimeBudget(memoryGiB: memoryGiB, contextTokens: tokens, availableBytes: localMemoryHeadroom) { return prepared }
        let entry = catalog.first { $0.id == settings.localRepository }
        return LocalInferenceBudget(weightBytes: entry?.textWeightBytes ?? entry?.weightBytes ?? 0,
            availableBytes: localMemoryHeadroom, residentBytes: localBackendResidentBytes,
            requestedMemoryGiB: memoryGiB, requestedContextTokens: tokens,
            responseTokens: settings.localResponseTokens, supportsEfficientKV: settings.localRepository.contains("Qwen3.5-4B"), optimizedTextRuntime: entry?.textWeightBytes != nil)
    }
    func localBudget(for entry: LocalModelCatalogEntry) -> LocalInferenceBudget {
        if entry.id == settings.localRepository { return localContextBudget() }
        return LocalInferenceBudget(weightBytes: entry.textWeightBytes ?? entry.weightBytes ?? 0,
            availableBytes: localMemoryHeadroom + localBackendResidentBytes, requestedMemoryGiB: settings.localMemoryGiB,
            responseTokens: settings.localResponseTokens, supportsEfficientKV: entry.id.contains("Qwen3.5-4B"), optimizedTextRuntime: entry.textWeightBytes != nil)
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
