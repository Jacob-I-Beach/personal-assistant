import Foundation

public struct ModelWorkIdentity: Sendable {
    public let conversationID: UUID
    public let turnID: UUID
    public let containsHealthData: Bool
    public init(conversationID: UUID, turnID: UUID, containsHealthData: Bool) {
        self.conversationID = conversationID; self.turnID = turnID; self.containsHealthData = containsHealthData
    }
}
public enum RemoteTaskEvent: Sendable {
    case transcript([Message])
    case receipt(ToolCall, ToolResult)
    case activity(String)
    case completed
}
/// The remote owner keeps running when this subscriber is cancelled. Only an
/// explicit stop request cancels the saved job on that computer.
public protocol RemoteTaskBackend: ModelBackend {
    func runTask(_ request: ModelRequest) -> AsyncThrowingStream<RemoteTaskEvent, any Error>
}
public struct CompanionRunRecord: Codable, Sendable {
    public var turnID: UUID
    public var connectionID: String
    public var payload: JSONValue
    public var jobID: String?
    public var status: String
    public var stopRequested: Bool
    public init(turnID: UUID, connectionID: String, payload: JSONValue) {
        self.turnID = turnID; self.connectionID = connectionID; self.payload = payload
        self.status = "queued"; self.stopRequested = false
    }
}
extension LocalStore {
    public func companionRun(_ turnID: UUID) throws -> CompanionRunRecord? {
        try database.execute("CREATE TABLE IF NOT EXISTS companion_runs(id TEXT PRIMARY KEY,payload BLOB NOT NULL)")
        guard let data = try database.execute("SELECT payload FROM companion_runs WHERE id=?", [.text(turnID.uuidString)]).first?[0].data else { return nil }
        return try Self.decode(CompanionRunRecord.self, data)
    }
    public func saveCompanionRun(_ value: CompanionRunRecord) throws {
        var value = value
        if try companionRun(value.turnID)?.stopRequested == true { value.stopRequested = true }
        try database.execute("INSERT INTO companion_runs(id,payload) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload", [.text(value.turnID.uuidString), .blob(try Self.encode(value))])
    }
}

/// Replaying a durable event sequence rebuilds the same message IDs. A reconnect
/// replaces this turn's projection instead of appending duplicate partial text.
public struct CompanionTranscript: Sendable {
    public private(set) var messages: [Message] = []
    public private(set) var cursor = 0
    private let jobID: UUID
    private let providerID: String
    private let health: Bool
    private var activeIndex: Int?
    private var roundStart = 0
    private var toolIDs = Set<String>()
    public init(jobID: UUID, providerID: String, health: Bool) { self.jobID = jobID; self.providerID = providerID; self.health = health }
    private func identifier(_ sequence: Int, role: Int = 0) -> UUID {
        let prefix = String(jobID.uuidString.prefix(24))
        return UUID(uuidString: prefix + String(format: "%012llX", Int64(sequence) * 4 + Int64(role)))!
    }
    private mutating func ensureAssistant(sequence: Int, date: Date) -> Int {
        if let activeIndex { return activeIndex }
        var message = Message(id: identifier(sequence), role: .assistant, text: "", state: .streaming, providerID: providerID, containsHealthData: health)
        message.createdAt = date; messages.append(message); activeIndex = messages.count - 1
        return messages.count - 1
    }
    public mutating func apply(_ event: JSONValue) throws -> (ToolCall, ToolResult)? {
        guard let value = event["seq"]?.numberValue, let sequence = Int(exactly: value), sequence > cursor else { return nil }
        guard sequence == cursor + 1 else { throw AssistantError.provider("Some computer progress is missing. Reconnect to recover the saved sequence.") }
        let date = event["recordedAt"]?.stringValue.flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
        defer { cursor = sequence }
        switch event["type"]?.stringValue {
        case "response_begin":
            // Only the current, uncommitted response can be replaced after retry.
            if let index = activeIndex, messages[index].state != .complete { messages.removeSubrange(roundStart...) }
            activeIndex = nil; roundStart = messages.count
        case "text_delta":
            guard let text = event["text"]?.stringValue else { break }
            let index = ensureAssistant(sequence: sequence, date: date)
            let key = event["item_id"]?.stringValue ?? "current"
            if let part = messages[index].responseParts.firstIndex(where: { $0.id == key }) { messages[index].responseParts[part].text += text }
            else { messages[index].responseParts.append(ResponsePart(id: key, text: text, phase: event["phase"]?.stringValue)) }
            messages[index].text = ResponsePresentation.text(in: messages[index].responseParts)
        case "continuation":
            let items = event["output"]?.arrayValue ?? []
            let index = ensureAssistant(sequence: sequence, date: date)
            messages[index].responseParts = ResponsePresentation.parts(from: items)
            messages[index].text = ResponsePresentation.text(in: messages[index].responseParts)
            // A multi-call turn has one provider output list; attach it once.
            messages[index].continuation = ProviderContinuation(providerID: providerID, items: items)
            messages[index].state = .complete
        case "executed_tool":
            guard let callData = event["call"], let raw = event["result"], let succeeded = raw["succeeded"]?.boolValue else { throw AssistantError.invalidTool("The computer returned an incomplete action receipt.") }
            let call = try JSONDecoder().decode(ToolCall.self, from: JSONEncoder().encode(callData))
            guard toolIDs.insert(call.id).inserted else { break }
            var result = ToolResult(callID: call.id, name: call.name, succeeded: succeeded, output: raw["output"] ?? .null)
            result.completedAt = date
            result.containsHealthData = raw["containsHealthData"]?.boolValue
            result.containsLocalOnlyContext = raw["containsLocalOnlyContext"]?.boolValue
            result.authorizedHealthDestination = raw["authorizedHealthDestination"]?.stringValue
            if let response = raw["userResponse"], response != .null { result.userResponse = try JSONDecoder().decode(Message.self, from: JSONEncoder().encode(response)) }
            let index = ensureAssistant(sequence: sequence, date: date)
            messages[index].toolCalls.append(call); messages[index].state = .complete
            var receipt = Message(id: identifier(sequence, role: 1), role: .tool, text: try result.modelText(), state: succeeded ? .complete : .failed, toolCallID: call.id, containsHealthData: health || result.containsHealthData == true)
            receipt.createdAt = date; messages.append(receipt)
            if let response = result.userResponse { messages.append(response) }
            activeIndex = nil
            return (call, result)
        case "status":
            if let index = activeIndex {
                switch event["status"]?.stringValue {
                case "completed": messages[index].state = .complete
                case "failed": messages[index].state = .failed; messages[index].failureReason = event["text"]?.stringValue
                case "cancelled", "interrupted": messages[index].state = .interrupted
                default: break
                }
            }
        default: break
        }
        return nil
    }
}
