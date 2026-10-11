#if DEBUG
import AssistantCore
import Foundation

extension AppModel {
    func installLongTaskFixture() async {
        guard let store else { return }
        settings.choice = .appleOnDevice; settings.automaticChatTitles = false
        var chat = Conversation(id: UUID(uuidString: "00000000-0000-4000-8000-000000000071")!, title: "Long task fixture")
        let user = Message(role: .user, text: "Read the earlier decisions")
        chat.messages = [user]
        do {
            for index in 1...5 {
                let call = ToolCall(id: "read-\(index)", name: "read_history", arguments: .object(["message_id": .string(UUID().uuidString), "offset": .string("0")]))
                chat.messages.append(Message(role: .assistant, text: "", toolCalls: [call]))
                let result = ToolResult(callID: call.id, name: call.name, succeeded: true, output: .object(["result": .array([.object(["title": .string("Project decision \(index)"), "text": .string("Keep the example concise and useful.")])])]))
                chat.messages.append(Message(role: .tool, text: try result.modelText(), toolCallID: call.id))
            }
            chat.messages += [Message(role: .assistant, text: "The decisions are saved."), Message(role: .user, text: "Use these decisions"), Message(role: .assistant, text: "The current request is complete.")]
            try await store.save(chat)
            var old = WorkTurn(id: user.id, conversationID: chat.id, userMessageID: user.id, backendID: "synthetic-long-task", goal: user.text)
            old.phase = .interrupted; try await store.saveWorkTurn(old)
            conversation = chat; draft = "Run the recovery example"
        } catch { errorMessage = error.localizedDescription }
    }
}
struct UILongTaskBackend: ModelBackend {
    var id: String { "synthetic-long-task" }
    var networkDestination: String? { nil }
    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        AsyncThrowingStream { output in
            let task = Task {
                do {
                    output.yield(.textDelta("An unfinished response."))
                    output.yield(.retrying(attempt: 1, maximum: 5))
                    try await Task.sleep(for: .seconds(4))
                    output.yield(.restartResponse)
                    output.yield(.textDelta("Recovered reply with saved work intact."))
                    output.yield(.completed); output.finish()
                } catch { output.finish(throwing: error) }
            }
            output.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
#endif
