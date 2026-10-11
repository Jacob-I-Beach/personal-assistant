#if DEBUG
import AssistantCore
import Foundation

extension AppModel {
    func installDailyWorkflowFixture() async {
        settings.choice = .appleOnDevice; settings.automaticChatTitles = false
        settings.calendarSourceIDs = ["fixture-calendar"]; settings.reminderSourceIDs = ["fixture-reminders"]
        planning.installFixture(); await planning.refreshHome(settings: settings)
        conversation = Conversation(); draft = "Plan the example session"
    }
}
struct UIDailyWorkflowBackend: ModelBackend {
    var questionOnly = false
    var id: String { "synthetic-daily-workflow" }
    var networkDestination: String? { nil }
    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        AsyncThrowingStream { output in
            let ids = Set(request.messages.filter { $0.message.role == .tool }.compactMap { $0.message.toolCallID })
            if !ids.contains("example-question") {
                output.yield(.toolCall(.init(id: "example-question", name: "request_input", arguments: .object(["question": .string("When should we work on it?"), "why": .string("Choose a time for the example session."), "kind": .string("choice"), "choices_json": .string("[\"Morning\",\"Afternoon\"]")]))))
            } else if questionOnly { output.yield(.textDelta("Your answer is saved in the conversation.")) }
            else if !ids.contains("example-save") {
                let start = Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: Date())!
                output.yield(.toolCall(.init(id: "example-save", name: "save_calendar_event", arguments: .object(["item_id": .string(""), "version": .string(""), "source_id": .string("fixture-calendar"), "title": .string("Example work session"), "start": .string(ISO8601DateFormatter().string(from: start)), "end": .string(ISO8601DateFormatter().string(from: start.addingTimeInterval(2700))), "location": .string(""), "notes": .string("Synthetic workflow rehearsal")]))))
            } else { output.yield(.textDelta("Your example session is saved.")) }
            output.yield(.completed); output.finish()
        }
    }
}
#endif
