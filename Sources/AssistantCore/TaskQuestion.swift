import Foundation

public struct TaskQuestion: Identifiable, Codable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable { case text, choice, photo, measurement }
    public enum State: String, Codable, Sendable { case pending, answered, skipped }
    public let id: UUID
    public let conversationID: UUID
    public let turnID: UUID
    public let callID: String
    public let title: String
    public let detail: String
    public let kind: Kind
    public let choices: [String]
    public let createdAt: Date
    public var state: State = .pending
    public var answer: Message?
    public init(conversationID: UUID, turnID: UUID, callID: String, title: String, detail: String, kind: Kind, choices: [String]) throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 240, detail.count <= 700,
              choices.count <= 5, choices.allSatisfy({ !$0.isEmpty && $0.count <= 120 }), Set(choices).count == choices.count else {
            throw AssistantError.invalidTool("Ask one focused question, with up to five short choices.")
        }
        id = UUID(); self.conversationID = conversationID; self.turnID = turnID; self.callID = callID
        self.title = title; self.detail = detail; self.kind = kind; self.choices = choices; createdAt = Date()
    }
}
extension LocalStore {
    private func ensureQuestions() throws {
        try database.execute("CREATE TABLE IF NOT EXISTS task_questions(id TEXT PRIMARY KEY,conversation_id TEXT NOT NULL,turn_id TEXT NOT NULL,call_id TEXT NOT NULL,payload BLOB NOT NULL,UNIQUE(turn_id,call_id))")
    }
    public func saveQuestion(_ question: TaskQuestion) throws -> TaskQuestion {
        try ensureQuestions()
        if let data = try database.execute("SELECT payload FROM task_questions WHERE turn_id=? AND call_id=?", [.text(question.turnID.uuidString), .text(question.callID)]).first?[0].data {
            let existing = try Self.decode(TaskQuestion.self, data)
            guard existing.title == question.title, existing.detail == question.detail, existing.kind == question.kind, existing.choices == question.choices, existing.conversationID == question.conversationID else { throw AssistantError.invalidTool("This question changed while waiting for an answer.") }
            return existing
        }
        try database.execute("INSERT INTO task_questions(id,conversation_id,turn_id,call_id,payload) VALUES(?,?,?,?,?)", [.text(question.id.uuidString), .text(question.conversationID.uuidString), .text(question.turnID.uuidString), .text(question.callID), .blob(try Self.encode(question))])
        return question
    }
    public func question(_ id: UUID) throws -> TaskQuestion {
        try ensureQuestions()
        guard let data = try database.execute("SELECT payload FROM task_questions WHERE id=?", [.text(id.uuidString)]).first?[0].data else { throw AssistantError.invalidTool("That question is no longer available.") }
        return try Self.decode(TaskQuestion.self, data)
    }
    public func pendingQuestions() throws -> [TaskQuestion] {
        try ensureQuestions()
        let eligible = Set(try unfinishedWork().map(\.id))
        return try database.execute("SELECT payload FROM task_questions ORDER BY rowid DESC LIMIT 100").map { try Self.decode(TaskQuestion.self, $0[0].data!) }
            .filter { $0.state == .pending && eligible.contains($0.turnID) }
    }
    public func answerQuestion(_ id: UUID, text: String, captureIDs: [UUID], skip: Bool) throws -> TaskQuestion {
        var value = try question(id)
        guard value.state == .pending, let work = try workTurn(value.turnID), [.running, .interrupted].contains(work.phase),
              try loadConversation(value.conversationID).messages.last(where: \.isRequest)?.id == work.userMessageID else {
            throw AssistantError.invalidTool("This question belongs to an earlier or completed task.")
        }
        guard text.utf8.count <= 8000, captureIDs.count <= 1, skip || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !captureIDs.isEmpty else { throw AssistantError.invalidTool("Enter an answer, choose a photo, or skip the question.") }
        for id in captureIDs { _ = try loadCapture(id) }
        let chat = try loadConversation(value.conversationID)
        let source = try message(work.userMessageID, in: value.conversationID)
        var answer = Message(role: .user, text: skip ? "" : text, captureIDs: skip ? [] : captureIDs, containsHealthData: chat.containsHealthData, containsLocalOnlyContext: chat.networkDisabled || source.containsLocalOnlyContext)
        answer.replyToTaskID = value.turnID
        value.state = skip ? .skipped : .answered; value.answer = skip ? nil : answer
        try database.execute("UPDATE task_questions SET payload=? WHERE id=?", [.blob(try Self.encode(value)), .text(id.uuidString)])
        return value
    }
}
