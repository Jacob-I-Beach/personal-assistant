import AssistantCore
import Foundation

extension AppModel {
    var supportedReasoningEfforts: [ReasoningEffort] {
        if settings.choice == .chatGPT {
            return chatGPTModels.first(where: { $0.id == settings.chatGPTModel })?.reasoningEfforts
                ?? ReasoningEffort.documented(for: settings.chatGPTModel)
        }
        if settings.choice == .openAI { return ReasoningEffort.documented(for: settings.openAIModel) }
        return []
    }
    var selectedReasoningEffort: ReasoningEffort? {
        let id = settings.choice == .chatGPT ? settings.chatGPTModel : settings.openAIModel
        if let raw = settings.reasoningByModel[id], let value = ReasoningEffort(rawValue: raw), supportedReasoningEfforts.contains(value) { return value }
        return supportedReasoningEfforts.contains(.medium) ? .medium : supportedReasoningEfforts.first
    }
    func chooseReasoningEffort(_ effort: ReasoningEffort) {
        guard !isRunning, supportedReasoningEfforts.contains(effort) else { return }
        var next = settings
        next.reasoningByModel[settings.choice == .chatGPT ? settings.chatGPTModel : settings.openAIModel] = effort.rawValue
        do { try saveSettings(next) } catch { errorMessage = error.localizedDescription }
    }
}
