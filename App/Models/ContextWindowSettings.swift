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
        let entry = selection.choice == .chatGPT ? chatGPTModels.first { $0.id == selection.chatGPTModel } : nil
        return ModelContextBudget(model: selection.choice == .compatibleServer ? "" : selection.contextModelID,
            advertisedWindow: entry?.contextWindow, advertisedMaximumWindow: entry?.maximumContextWindow,
            requestedInputTokens: selection.contextTokensByModel[selection.contextPreferenceKey])
    }
}

struct ContextWindowView: View {
    var body: some View { ReasoningEffortView(focusContext: true) }
}
