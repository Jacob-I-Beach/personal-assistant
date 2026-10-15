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
        let computerOwned = try await store.workTurn(identity.turnID).map { TaskRoutePolicy.savedOwner(backendID: $0.backendID, destination: $0.destination) == .computer } ?? false
        await refresh()
        if question.state == .pending, computerOwned {
            try await store.setOperationWaitingForReview(turnID: identity.turnID, callID: identity.callID, waiting: true)
            return ToolResult(callID: call.id, name: call.name, succeeded: true, output: .object(["status": .string("pending_input"), "question_id": .string(question.id.uuidString)]))
        }
        if question.state == .pending {
            _ = try await reviewNativeAction(.init(kind: .question, title: "Your answer is needed", detail: question.title, arguments: call.arguments, questionID: question.id))
            try Task.checkCancellation()
            question = try await store.question(question.id)
        }
        guard question.state != .pending else { throw AssistantError.invalidTool("This question is still waiting for an answer.") }
        if computerOwned { return try await computerQuestionResult(question) }
        return Self.questionResult(question, callID: call.id, name: call.name)
    }
    static func questionResult(_ question: TaskQuestion, callID: String, name: String) -> ToolResult {
        var result = ToolResult(callID: callID, name: name, succeeded: true, output: .object([
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
    private func computerQuestionResult(_ question: TaskQuestion) async throws -> ToolResult {
        guard let store, let run = try await store.companionRun(question.turnID), let jobID = run.jobID,
              let connection = settings.companion, run.connectionID == connection.destination,
              settings.useComputer, !settings.localOnly else { throw AssistantError.networkNotAuthorized }
        var result = Self.questionResult(question, callID: question.callID, name: "request_input")
        guard result.containsLocalOnlyContext != true else { throw AssistantError.networkNotAuthorized }
        let chat = try await store.loadConversation(question.conversationID)
        guard result.containsHealthData != true || chat.allowedHealthDestinations.contains(connection.destination) else { throw AssistantError.networkNotAuthorized }
        let client = try CompanionClient(baseURL: connection.baseURL, fingerprint: connection.certificateSHA256, token: CredentialStore.read(account: connection.credentialAccount))
        var photos: [JSONValue] = []
        for capture in question.answer?.captureIDs ?? [] {
            let data = try await store.imageData(capture)
            let file = try await client.json("/v1/jobs/" + jobID + "/files", method: "POST", body: .object(["id": .string(capture.uuidString), "filename": .string(capture.uuidString + ".jpg"), "data_base64": .string(data.base64EncodedString()), "contains_health_data": .bool(result.containsHealthData == true)]))
            photos.append(file)
        }
        if !photos.isEmpty, var values = result.output.objectValue {
            values["files"] = .array(photos); values["answer_image_ids"] = .array(photos.compactMap { $0["id"] })
            result.output = .object(values)
        }
        return result
    }
    func openQuestion(_ question: TaskQuestion) {
        if nativeAction != nil { return }
        nativeReviewVisible = true
        AppFeedback.play(.question)
        nativeAction = .init(kind: .question, title: "Your answer is needed", detail: question.title, arguments: .object([:]), questionID: question.id)
    }
    func submitQuestion(_ id: UUID, text: String, captureIDs: [UUID], skip: Bool) async throws {
        guard let store else { throw AssistantError.provider("App storage is unavailable.") }
        let question = try await store.answerQuestion(id, text: text, captureIDs: captureIDs, skip: skip)
        if let run = try await store.companionRun(question.turnID), let jobID = run.jobID,
           let connection = settings.companion, run.connectionID == connection.destination, !settings.localOnly, settings.useComputer {
            let client = try CompanionClient(baseURL: connection.baseURL, fingerprint: connection.certificateSHA256, token: CredentialStore.read(account: connection.credentialAccount))
            let path = "/v1/jobs/" + jobID, operation = try await client.json(path + "/operations/" + question.callID)
            if operation["result"] == nil || operation["result"] == .null {
                let result = try await computerQuestionResult(question)
                let value = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(result))
                _ = try await client.json(path + "/operations/" + question.callID + "/result", method: "POST", body: value)
            }
        }
        if let request = nativeAction, request.questionID == id, isPendingNativeAction(request.id) {
            resolveNativeAction(skip ? "skipped" : "answered", for: request.id)
        } else {
            if !isRunning || conversation.id == question.conversationID { questionResumeAfterDismiss = try await store.workTurn(question.turnID) }
            nativeAction = nil
        }
        await refresh()
    }
}
