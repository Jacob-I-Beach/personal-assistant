import AssistantCore
import Foundation

enum QuestionTools {
    static let list = NativeTools.definition("list_task_questions", "Read saved questions awaiting the user's answer in this chat. Questions from other chats are excluded. Pending is not permission or completion.", [:])
    static let answer = NativeTools.definition("answer_task_question", "When the current user's message answers an existing question in this chat, save its exact answer quote and deliver it to that original task. Do not use for hypotheticals, guesses, or approvals. This cannot approve an external action. Use list_task_questions for the question ID.", ["question_id": "Exact saved question UUID", "answer_quote": "Exact answer text from the current user's message; empty only for a requested photo supplied in that message."])
    static let request = NativeTools.definition("request_input", "Ask one focused question when an answer, choice, photo or measurement is needed to finish this task. The user can type another answer, skip, or leave it for later; the question and answer are saved with the task. This is not approval to send, purchase or change external data.", ["question": "One clear question, up to 240 characters", "why": "Explain what this unblocks, up to 700 characters; specify units for a measurement", "kind": "text, choice, photo, or measurement", "choices_json": "JSON array of 0–5 short strings. Users can always type an answer."])
    static var definitions: [ToolDefinition] { [request, list, answer] }
}
extension AppModel {
    func executeQuestionAnswerTool(_ call: ToolCall, conversationID: UUID, destination: String?) async throws -> ToolResult {
        guard let store else { throw AssistantError.provider("Question storage is unavailable.") }
        if call.name == QuestionTools.list.name {
            var questions: [TaskQuestion] = []
            for question in try await store.pendingQuestions() where question.conversationID == conversationID {
                guard let work = try await store.workTurn(question.turnID), destination == nil || work.containsLocalOnlyContext == false && work.containsHealthData == false else { continue }
                questions.append(question)
            }
            return .init(callID: call.id, name: call.name, succeeded: true, output: .array(questions.map { .object(["question_id": .string($0.id.uuidString), "task_id": .string($0.turnID.uuidString), "question": .string($0.title), "why": .string($0.detail), "kind": .string($0.kind.rawValue)]) }))
        }
        guard let scope = ToolExecutionContext.current, let id = call.arguments["question_id"]?.stringValue.flatMap(UUID.init(uuidString:)),
              let quote = call.arguments["answer_quote"]?.stringValue else { throw AssistantError.invalidTool("Use the saved question ID and an exact answer quote.") }
        let question = try await store.question(id), chat = try await store.loadConversation(conversationID)
        guard question.conversationID == conversationID, let target = try await store.workTurn(question.turnID),
              destination == nil || target.containsLocalOnlyContext == false && target.containsHealthData == false,
              let source = chat.messages.last(where: { $0.role == .user && ($0.id == scope.turnID || $0.replyToTaskID == scope.turnID) }) else { throw AssistantError.invalidTool("The answer must come from this task's actual user message.") }
        let answered = try await store.answerQuestion(id, text: quote, captureIDs: question.kind == .photo ? Array(source.captureIDs.prefix(1)) : [], skip: false, sourceMessageID: source.id)
        var delivered = false
        if destination?.hasPrefix("computer:") == true {
            do { delivered = try await deliverComputerQuestion(answered) }
            catch { if !CompanionObservationPolicy.shouldRetry(error) { throw error }; await recordQueuedAnswer(answered) }
        } else if target.backendID.hasPrefix("companion:") { await recordQueuedAnswer(answered) }
        await refresh()
        return .init(callID: call.id, name: call.name, succeeded: true, output: .object(["status": .string(delivered ? "answer_delivered" : "answer_saved"), "question_id": .string(id.uuidString), "task_id": .string(question.turnID.uuidString), "source_message_id": .string(source.id.uuidString), "notice": .string("This supplies the quoted context only, never approval for an external action.")]))
    }
    private func recordQueuedAnswer(_ question: TaskQuestion) async {
        if var work = try? await store?.workTurn(question.turnID), [.running, .interrupted].contains(work.phase) {
            work.phase = .interrupted; work.interruptionKind = "computer_detached"; work.reason = "Your answer is saved and will reach the original computer task when reconnected."
            try? await store?.saveWorkTurn(work)
        }
        noticeMessage = "Your answer is saved. It will sync with the computer when the connection returns."
    }
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
        result.userResponse = question.answerSourceMessageID == nil ? question.answer : nil
        if let source = question.answerSourceMessageID, var values = result.output.objectValue { values["source_message_id"] = .string(source.uuidString); result.output = .object(values) }
        result.containsLocalOnlyContext = question.answer?.containsLocalOnlyContext
        result.containsHealthData = question.answer?.containsHealthData
        return result
    }
    private func deliverComputerQuestion(_ question: TaskQuestion) async throws -> Bool {
        guard let store, let run = try await store.companionRun(question.turnID), let jobID = run.jobID,
              let connection = settings.companion, run.connectionID == connection.destination, !settings.localOnly, settings.useComputer else { return false }
        let client = try CompanionClient(baseURL: connection.baseURL, fingerprint: connection.certificateSHA256, token: CredentialStore.read(account: connection.credentialAccount))
        let path = "/v1/jobs/" + jobID, operation = try await client.json(path + "/operations/" + question.callID, timeout: 4)
        if operation["result"] == nil || operation["result"] == .null {
            let result = try await computerQuestionResult(question)
            let value = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(result))
            _ = try await client.json(path + "/operations/" + question.callID + "/result", method: "POST", body: value, timeout: 4)
        }
        return true
    }
    private func computerQuestionResult(_ question: TaskQuestion) async throws -> ToolResult {
        guard let store, let run = try await store.companionRun(question.turnID), let jobID = run.jobID,
              let connection = settings.companion, run.connectionID == connection.destination,
              settings.useComputer, !settings.localOnly else { throw AssistantError.networkNotAuthorized }
        var result = Self.questionResult(question, callID: question.callID, name: "request_input")
        guard result.containsLocalOnlyContext != true else { throw AssistantError.networkNotAuthorized }
        let chat = try await store.loadConversation(question.conversationID)
        guard chat.allowedNetworkDestinations.contains(connection.destination), !chat.networkDisabled else { throw AssistantError.networkNotAuthorized }
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
        if nativeAction != nil || needsNetworkConsent || isPreparingRoute { return }
        nativeReviewVisible = true
        AppFeedback.play(.question)
        nativeAction = .init(kind: .question, title: "Your answer is needed", detail: question.title, arguments: .object([:]), questionID: question.id)
    }
    func submitQuestion(_ id: UUID, text: String, captureIDs: [UUID], skip: Bool) async throws {
        guard let store else { throw AssistantError.provider("App storage is unavailable.") }
        let question = try await store.answerQuestion(id, text: text, captureIDs: captureIDs, skip: skip)
        do { _ = try await deliverComputerQuestion(question) }
        catch { if !CompanionObservationPolicy.shouldRetry(error) { throw error }; await recordQueuedAnswer(question) }
        if let request = nativeAction, request.questionID == id, isPendingNativeAction(request.id) {
            resolveNativeAction(skip ? "skipped" : "answered", for: request.id)
        } else {
            if !isRunning || conversation.id == question.conversationID { questionResumeAfterDismiss = try await store.workTurn(question.turnID) }
            nativeAction = nil
        }
        await refresh()
    }
}
