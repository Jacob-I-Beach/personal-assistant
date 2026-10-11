#if DEBUG
import AssistantCore
import Foundation

extension AppModel {
    func installCoherenceFixture() async {
        guard let store else { return }
        settings.choice = .chatGPT; settings.chatGPTAccountID = "synthetic-account"; settings.chatGPTModel = "gpt-6.1-sol"
        settings.automaticChatTitles = false; settings.confirmNewConnectedChats = false; settings.localOnly = false
        settings.continueInBackground = false; settings.taskNotifications = false
        accounts = [.init(id: "synthetic-account", label: "Synthetic test account", isConnected: true)]
        chatGPTModels = (try? ChatGPTModel.catalog(from: Data(#"{"models":[{"slug":"gpt-6.1-sol","display_name":"GPT-6.1-Sol","visibility":"list","context_window":1050000}]}"#.utf8))) ?? []
        conversation = Conversation(title: "Coherent interaction fixture")
        conversation.messages = [Message(role: .user, text: "An earlier synthetic question"), Message(role: .assistant, text: "An earlier synthetic answer.")]
        try? await store.save(conversation)
        draft = ""
    }
}
struct UICoherenceBackend: ModelBackend {
    var id: String { "synthetic-coherence-fixture" }
    var networkDestination: String? { "chatgpt-account:synthetic-account" }
    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        AsyncThrowingStream { output in
            output.yield(.transportProgress(64))
            output.yield(.textDelta("Your synthetic request started without another connection prompt."))
            output.yield(.completed); output.finish()
        }
    }
}
#endif
