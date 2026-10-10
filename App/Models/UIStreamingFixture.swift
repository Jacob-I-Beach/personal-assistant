#if DEBUG
import AssistantCore
import Foundation

extension AppModel {
    func installStreamingFixture() async {
        guard let store else { return }
        settings.choice = .appleOnDevice; settings.automaticChatTitles = false
        settings.weatherFollowsLocation = false; settings.weatherPlace = nil
        var chat = Conversation(id: UUID(uuidString: "00000000-0000-4000-8000-000000000060")!, title: "Streaming fixture")
        chat.messages = [Message(role: .user, text: "Earlier synthetic context"),
            Message(role: .assistant, text: (1...45).map { "Earlier paragraph \($0). This saved text gives the reading position a stable reference above the live answer." }.joined(separator: "\n\n"))]
        do { try await store.save(chat); conversation = chat; draft = "Stream the synthetic example" }
        catch { errorMessage = error.localizedDescription }
    }
}
struct UIStreamingBackend: ModelBackend {
    var id: String { "synthetic-streaming-fixture" }
    var networkDestination: String? { nil }
    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        AsyncThrowingStream { output in
            let task = Task {
                do {
                    let introduction = ResponsePart(id: "intro", text: "I’m checking a synthetic reference, then streaming a long answer.", phase: "commentary")
                    output.yield(.responseContent([introduction, .init(id: "web", web: .init(status: "in_progress", queries: ["Synthetic reference"]))]))
                    try await Task.sleep(for: .seconds(2))
                    let web = ResponsePart(id: "web", web: .init(status: "completed", queries: ["Synthetic reference"]))
                    var text = ""
                    // Keep real growth throughout the gesture checks without producing
                    // pages faster than XCUITest's mandatory between-gesture idle waits.
                    for index in 1...240 {
                        try Task.checkCancellation()
                        text += "Line \(index). More of the example.\n\n"
                        output.yield(.responseContent([introduction, web, .init(id: "answer", text: text, phase: "final_answer")]))
                        try await Task.sleep(for: .milliseconds(250))
                    }
                    output.yield(.completed); output.finish()
                } catch { output.finish(throwing: error) }
            }
            output.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
#endif
