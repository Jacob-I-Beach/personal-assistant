import AssistantCore
import Foundation

enum QuestionTools {
    static let request = NativeTools.definition("request_input", "Ask one focused question when an answer, choice, photo or measurement is needed to finish this task. The user can type another answer, skip, or leave it for later; the question and answer are saved with the task. This is not approval to send, purchase or change external data.", ["question": "One clear question, up to 240 characters", "why": "Explain what this unblocks, up to 700 characters; specify units for a measurement", "kind": "text, choice, photo, or measurement", "choices_json": "JSON array of 0–5 short strings. Users can always type an answer."])
}
extension AppModel {
    func executeQuestionTool(_ call: ToolCall, conversationID: UUID) async throws -> ToolResult {
        guard let store, let identity = ToolExecutionContext.current,
              let kind = TaskQuestion.Kind(rawValue: call.arguments["kind"]?.stringValue ?? ""),
              let values = try JSONValue.parse(call.arguments["choices_json"]!.stringValue!).arrayValue,
              values.allSatisfy({ $0.stringValue != nil }) else { throw AssistantError.invalidTool("Use a supported question type and a JSON list of choices.") }
        let proposed = try TaskQuestion(conversationID: conversationID, turnID: identity.turnID, callID: identity.callID, title: call.arguments["question"]!.stringValue!, detail: call.arguments["why"]!.stringValue!, kind: kind, choices: values.compactMap(\.stringValue))
        var question = try await store.saveQuestion(proposed)
        await refresh()
        if question.state == .pending {
            _ = try await reviewNativeAction(.init(kind: .question, title: "Your answer is needed", detail: question.title, arguments: call.arguments, questionID: question.id))
            try Task.checkCancellation()
            question = try await store.question(question.id)
        }
        guard question.state != .pending else { throw AssistantError.invalidTool("This question is still waiting for an answer.") }
        var result = ToolResult(callID: call.id, name: call.name, succeeded: true, output: .object([
            "status": .string(question.state == .skipped ? "skipped" : "answered"), "question": .string(question.title),
            "answer": question.answer.map { .string($0.text) } ?? .null,
            "source_message_id": question.answer.map { .string($0.id.uuidString) } ?? .null,
            "photos_supplied": .number(Double(question.answer?.captureIDs.count ?? 0)),
            "notice": .string("This answer supplies context only. It is not authorization for an external action. A skipped question must not be treated as an answer.")]))
        result.userResponse = question.answer
        result.containsLocalOnlyContext = question.answer?.containsLocalOnlyContext
        result.containsHealthData = question.answer?.containsHealthData
        return result
    }
    func openQuestion(_ question: TaskQuestion) {
        guard !isRunning || conversation.id == question.conversationID else { return }
        if nativeAction != nil { return }
        nativeReviewVisible = true
        AppFeedback.play(.question)
        nativeAction = .init(kind: .question, title: "Your answer is needed", detail: question.title, arguments: .object([:]), questionID: question.id)
    }
    func submitQuestion(_ id: UUID, text: String, captureIDs: [UUID], skip: Bool) async throws {
        guard let store else { throw AssistantError.provider("App storage is unavailable.") }
        let question = try await store.answerQuestion(id, text: text, captureIDs: captureIDs, skip: skip)
        if let request = nativeAction, request.questionID == id, isPendingNativeAction(request.id) {
            resolveNativeAction(skip ? "skipped" : "answered", for: request.id)
        } else {
            questionResumeAfterDismiss = try await store.workTurn(question.turnID)
            nativeAction = nil
        }
        await refresh()
    }
}
