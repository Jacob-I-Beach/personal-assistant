#if DEBUG
import AssistantCore
import Foundation

extension AppModel {
    func installRecovery09Fixture() async {
        guard let store else { return }
        settings.choice = .appleOnDevice; settings.automaticChatTitles = false; settings.taskNotifications = false
        let chatID = UUID(uuidString: "00000000-0000-4000-8000-000000000091")!
        if ProcessInfo.processInfo.arguments.contains("--ui-recovery09-seed") || (try? await store.loadConversation(chatID)) == nil {
            var chat = Conversation(id: chatID, title: "Saved background task")
            let user = Message(role: .user, text: "Finish the saved research")
            chat.messages = [user, Message(role: .assistant, text: "The earlier work stays saved.", state: .interrupted)]
            var work = WorkTurn(id: user.id, conversationID: chat.id, userMessageID: user.id, backendID: UIRecovery09Backend().id, goal: user.text)
            work.phase = .interrupted; work.resumes = 3; work.rounds = 12
            work.reason = "The background session ended. Your progress is saved."
            try? await store.save(chat); try? await store.saveWorkTurn(work)
            ReplyReturnRoute.remember(chat.id)
        }
        conversation = Conversation(); draft = ""
    }
}
struct UIRecovery09Backend: ModelBackend {
    let id = "synthetic-recovery09"
    var networkDestination: String? { nil }
    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        AsyncThrowingStream { output in output.yield(.textDelta("Your saved work continued.")); output.yield(.completed); output.finish() }
    }
}
#endif
