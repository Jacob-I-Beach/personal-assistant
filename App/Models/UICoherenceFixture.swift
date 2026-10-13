#if DEBUG
import AssistantCore
import Foundation
import UIKit

extension AppModel {
    func installCoherenceFixture() async {
        guard let store else { return }
        settings.choice = .chatGPT; settings.chatGPTAccountID = "synthetic-account"; settings.chatGPTModel = "gpt-6.1-sol"
        settings.automaticChatTitles = false; settings.confirmNewConnectedChats = false; settings.localOnly = false
        settings.continueInBackground = false; settings.taskNotifications = false
        accounts = [.init(id: "synthetic-account", label: "Synthetic test account", isConnected: true)]
        chatGPTModels = (try? ChatGPTModel.catalog(from: Data(#"{"models":[{"slug":"gpt-6.1-sol","display_name":"GPT-6.1-Sol","visibility":"list","context_window":272000,"max_context_window":1050000},{"slug":"limited-context-fixture","display_name":"Limited context model","visibility":"list","context_window":128000,"max_context_window":268384}]}"#.utf8))) ?? []
        conversation = Conversation(title: "Coherent interaction fixture")
        conversation.messages = [Message(role: .user, text: "An earlier synthetic question"), Message(role: .assistant, text: "An earlier synthetic answer.")]
        if ProcessInfo.processInfo.arguments.contains("--ui-computer-account") {
            let connection = CompanionConnection(baseURL: URL(string: "https://127.0.0.1:1")!, certificateSHA256: String(repeating: "a", count: 64),
                serverID: "synthetic-server", deviceID: "synthetic-phone", profileID: "synthetic-profile", name: "Test computer")
            settings.companion = connection; settings.useComputer = true; settings.chatGPTAccountID = nil; accounts = []
            try? applyComputerAccount(.object(["status": .string("connected"), "sharing": .bool(true), "profileId": .string(connection.profileID),
                "identity": .object(["email": .string("fixture@example.test")])]), connection: connection)
            conversation.messages = []
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-published-file") {
            let id = UUID(uuidString: "00000000-0000-4000-8000-000000000112")!
            if (try? await store.workspaceFile(id)) == nil {
                let image = UIGraphicsImageRenderer(size: CGSize(width: 360, height: 600)).image { context in
                    UIColor.darkGray.setFill(); context.cgContext.fill(CGRect(x: 0, y: 0, width: 360, height: 600))
                    UIColor.systemIndigo.setFill(); context.cgContext.fill(CGRect(x: 16, y: 20, width: 328, height: 100))
                    ("Synthetic screen" as NSString).draw(at: CGPoint(x: 30, y: 54), withAttributes: [.font: UIFont.systemFont(ofSize: 28), .foregroundColor: UIColor.white])
                    UIColor.systemGray.setFill(); context.cgContext.fill(CGRect(x: 16, y: 140, width: 328, height: 430))
                }
                if let data = image.pngData() {
                    try? await store.saveWorkspaceFile(WorkspaceFile(id: id, filename: "synthetic-screen.png", mediaType: "image/png", byteCount: data.count, text: "", conversationID: conversation.id), data: data)
                }
            }
            conversation.messages = [Message(role: .user, text: "Show the screenshot in chat."), Message(role: .assistant, text: "Here is the requested screenshot.", fileIDs: [id])]
        }
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
