import AppIntents
import AssistantCore
import Foundation

struct AskAssistantIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Personal Assistant"
    static let description = IntentDescription("Open a request in your private assistant using your selected model.")
    static let supportedModes: IntentModes = [.foreground(.immediate)]
    @Parameter(title: "Request") var request: String
    @AppDependency var model: AppModel

    @MainActor
    func perform() async throws -> some IntentResult {
        try await model.waitUntilReady()
        guard !model.isRunning, !model.needsNetworkConsent else { throw AssistantError.busy }
        guard !request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .result() }
        model.newConversation()
        model.draft = request; model.draftChanged(); model.send()
        return .result()
    }
}

struct AssistantShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AskAssistantIntent(), phrases: ["Ask \(.applicationName)", "Start a request in \(.applicationName)"],
                    shortTitle: "Ask Assistant", systemImageName: "bubble.left.and.bubble.right")
    }
}
