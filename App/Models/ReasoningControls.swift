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
    var selectedReasoningEffort: ReasoningEffort? { reasoningEffort(for: settings) }
    func reasoningEffort(for selection: ModelSettings) -> ReasoningEffort? {
        let id = selection.choice == .chatGPT ? selection.chatGPTModel : selection.openAIModel
        let supported = selection.choice == .chatGPT ? chatGPTModels.first(where: { $0.id == id })?.reasoningEfforts ?? ReasoningEffort.documented(for: id) : ReasoningEffort.documented(for: id)
        if let raw = selection.reasoningByModel[id], let value = ReasoningEffort(rawValue: raw), supported.contains(value) { return value }
        return supported.contains(.medium) ? .medium : supported.first
    }
    func chooseReasoningEffort(_ effort: ReasoningEffort) {
        guard !isRunning, supportedReasoningEfforts.contains(effort) else { return }
        var next = settings
        next.reasoningByModel[settings.choice == .chatGPT ? settings.chatGPTModel : settings.openAIModel] = effort.rawValue
        do { try saveSettings(next) } catch { errorMessage = error.localizedDescription }
    }
}
