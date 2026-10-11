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
        AppShortcut(intent: CaptureAssistantIntent(), phrases: ["Capture with \(.applicationName)", "Save a thought in \(.applicationName)"], shortTitle: "Capture a thought", systemImageName: "tray.and.arrow.down")
    }
}

struct AssistantChatEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Assistant chat")
    static let defaultQuery = AssistantChatQuery()
    let id: UUID
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}
struct AssistantChatQuery: EntityStringQuery {
    @AppDependency var model: AppModel
    @MainActor func entities(for identifiers: [UUID]) async throws -> [AssistantChatEntity] {
        try await model.waitUntilReady(); await model.refresh()
        return model.histories.filter { identifiers.contains($0.id) && $0.archivedAt == nil }.map { .init(id: $0.id, name: $0.title) }
    }
    @MainActor func suggestedEntities() async throws -> [AssistantChatEntity] {
        try await model.waitUntilReady(); await model.refresh()
        return model.histories.filter { $0.archivedAt == nil }.prefix(12).map { .init(id: $0.id, name: $0.title) }
    }
    @MainActor func entities(matching string: String) async throws -> [AssistantChatEntity] {
        try await model.waitUntilReady(); await model.refresh()
        return model.histories.filter { $0.archivedAt == nil && $0.title.localizedCaseInsensitiveContains(string) }.prefix(20).map { .init(id: $0.id, name: $0.title) }
    }
}
enum CaptureHandling: String, AppEnum {
    case saveOnly, later, answerNow
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Handling")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.saveOnly: "Save only", .later: "For later", .answerNow: "Answer now"]
}
struct CaptureAssistantIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture in Personal Assistant"
    static let description = IntentDescription("Save a thought or link to Inbox or a chosen chat, with or without an assistant reply.")
    static let supportedModes: IntentModes = [.foreground(.immediate)]
    @Parameter(title: "Thought") var text: String
    @Parameter(title: "Destination chat") var destination: AssistantChatEntity?
    @Parameter(title: "Handling", default: .saveOnly) var handling: CaptureHandling
    @AppDependency var model: AppModel
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        try await model.waitUntilReady()
        let mode = InboxHandling(rawValue: handling.rawValue) ?? .saveOnly
        _ = try await model.captureInbox(text: text, destination: destination?.id, handling: mode)
        if mode == .saveOnly { return .result(dialog: "Saved without starting a reply.") }
        return .result(dialog: "Captured in your assistant. Open the task to follow its progress.")
    }
}
