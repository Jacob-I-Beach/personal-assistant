#if DEBUG
import AssistantCore
import Foundation

extension AppModel {
    func installContinuityFixture() async {
        guard let store else { return }
        settings.choice = .appleOnDevice; settings.automaticChatTitles = false
        settings.weatherFollowsLocation = false; settings.weatherPlace = nil
        var chat = Conversation(id: UUID(uuidString: "00000000-0000-4000-8000-000000000061")!, title: "Continuity fixture")
        let user = Message(role: .user, text: "Prepare an example walking route")
        let call = ToolCall(id: "synthetic-route", name: "prepare_route", arguments: .object([:]))
        let origin = RoutePlace(name: "Example start", address: "Synthetic route origin", point: .init(latitude: 40.78, longitude: -73.97))
        let destination = RoutePlace(name: "Example park", address: "Synthetic route destination", point: .init(latitude: 40.79, longitude: -73.96))
        let route = PreparedRoute(conversationID: chat.id, sourceCallID: call.id, sourceMessageID: user.id, origin: origin, destination: destination, transport: "walking", distanceMeters: 1500, expectedTravelSeconds: 1200, points: [origin.point, destination.point], steps: ["Walk along the example path.", "Arrive at the example park."])
        do {
            let receipt = ToolResult(callID: call.id, name: call.name, succeeded: true, output: route.modelSummary())
            chat.messages = [user, Message(role: .assistant, text: "The example route is prepared.", toolCalls: [call]), Message(role: .tool, text: try receipt.modelText(), toolCallID: call.id)]
            try await store.save(chat); try await store.saveRoute(route)
            var work = WorkTurn(id: user.id, conversationID: chat.id, userMessageID: user.id, backendID: "synthetic-continuity-fixture", goal: user.text)
            work.phase = .interrupted; work.reason = "Synthetic interruption after route preparation"
            try await store.saveWorkTurn(work)
            var note = SavedMemory(id: UUID(uuidString: "00000000-0000-4000-8000-000000000062")!, title: "Example preference", text: "Use short examples")
            try await store.saveMemory(note); note.text = "Use detailed examples"; try await store.saveMemory(note)
            conversation = chat
        } catch { errorMessage = error.localizedDescription }
    }
    func installBackgroundFixture() async {
        settings.choice = .appleOnDevice; settings.automaticChatTitles = false
        conversation = Conversation(); draft = "Continue after the app returns"
    }
}
struct UIContinuityBackend: ModelBackend {
    var id: String { "synthetic-continuity-fixture" }
    var networkDestination: String? { nil }
    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        AsyncThrowingStream { output in
            output.yield(.textDelta("The saved route is ready. Open it when you’re ready.")); output.yield(.completed); output.finish()
        }
    }
}
struct UIBackgroundBackend: ModelBackend {
    var id: String { "synthetic-background-fixture" }
    var networkDestination: String? { nil }
    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        AsyncThrowingStream { output in
            let task = Task {
                do {
                    if request.messages.contains(where: { $0.message.role == .assistant && $0.message.text.contains("Progress saved before leaving.") }) {
                        output.yield(.textDelta("Continued from saved progress."))
                    } else {
                        output.yield(.textDelta("Progress saved before leaving."))
                        try await Task.sleep(for: .seconds(50))
                    }
                    output.yield(.completed); output.finish()
                } catch { output.finish(throwing: error) }
            }
            output.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
#endif
