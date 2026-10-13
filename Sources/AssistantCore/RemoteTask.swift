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
    case transportProgress(Int)
    case completed
}
/// The remote owner keeps running when this subscriber is cancelled. Only an
/// explicit stop request cancels the saved job on that computer.
public protocol RemoteTaskBackend: ModelBackend {
    func runTask(_ request: ModelRequest) -> AsyncThrowingStream<RemoteTaskEvent, any Error>
}
public enum CompanionObservationPolicy {
    public static func shouldRetry(_ error: any Error) -> Bool {
        let value = error as NSError
        return value.domain == NSURLErrorDomain && [NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost,
            NSURLErrorNotConnectedToInternet, NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost,
            NSURLErrorDNSLookupFailed].contains(value.code)
    }
}
public struct CompanionRunRecord: Codable, Sendable {
    public var turnID: UUID
    public var connectionID: String
    public var payload: JSONValue
    public var jobID: String?
    public var status: String
    public var stopRequested: Bool
    public var lastSyncedCursor: Int?
    /// These states need observation of the same job, never a new model run.
    /// A completed job may still have unseen events or files on the phone.
    public var canReconnect: Bool { !stopRequested && !["failed", "cancelled", "interrupted"].contains(status) }
    public init(turnID: UUID, connectionID: String, payload: JSONValue) {
        self.turnID = turnID; self.connectionID = connectionID; self.payload = payload
        self.status = "queued"; self.stopRequested = false; self.lastSyncedCursor = 0
    }
}

/// Never replace a saved transcript with an older prefix while replaying pages.
/// Old records without a cursor wait for the initial server snapshot boundary.
public struct CompanionReplayGate: Sendable {
    private var boundary: Int?
    public init(lastSyncedCursor: Int?) { boundary = lastSyncedCursor }
    public mutating func canPublish(cursor: Int, snapshotCursor: Int) -> Bool {
        if boundary == nil { boundary = snapshotCursor }
        return cursor >= (boundary ?? 0)
    }
}
extension LocalStore {
    public func computerToolWorkspace(_ turnID: UUID) throws -> [String: String]? {
        try database.execute("CREATE TABLE IF NOT EXISTS computer_tool_workspaces(id TEXT PRIMARY KEY,payload BLOB NOT NULL)")
        guard let data = try database.execute("SELECT payload FROM computer_tool_workspaces WHERE id=?", [.text(turnID.uuidString)]).first?[0].data else { return nil }
        return try Self.decode([String: String].self, data)
    }
    public func saveComputerToolWorkspace(_ turnID: UUID, jobID: String, destination: String) throws {
        _ = try computerToolWorkspace(turnID)
        try database.execute("INSERT INTO computer_tool_workspaces(id,payload) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload", [.text(turnID.uuidString), .blob(try Self.encode(["job_id": jobID, "destination": destination]))])
    }
    public func markComputerToolStop(_ turnID: UUID, delivered: Bool = false) throws {
        guard var value = try computerToolWorkspace(turnID) else { return }
        value["stop_requested"] = "true"; value["stop_delivered"] = delivered ? "true" : "false"
        try database.execute("UPDATE computer_tool_workspaces SET payload=? WHERE id=?", [.blob(try Self.encode(value)), .text(turnID.uuidString)])
    }
    public func pendingComputerToolStops(destination: String) throws -> [(UUID, String)] {
        _ = try computerToolWorkspace(UUID())
        return try database.execute("SELECT id,payload FROM computer_tool_workspaces").compactMap { row in
            guard let id = row[0].text.flatMap(UUID.init(uuidString:)), let data = row[1].data else { return nil }
            let value = try Self.decode([String: String].self, data)
            guard value["destination"] == destination, value["stop_requested"] == "true", value["stop_delivered"] != "true", let job = value["job_id"] else { return nil }
            return (id, job)
        }
    }
    public func companionRun(_ turnID: UUID) throws -> CompanionRunRecord? {
        try database.execute("CREATE TABLE IF NOT EXISTS companion_runs(id TEXT PRIMARY KEY,payload BLOB NOT NULL)")
        guard let data = try database.execute("SELECT payload FROM companion_runs WHERE id=?", [.text(turnID.uuidString)]).first?[0].data else { return nil }
        return try Self.decode(CompanionRunRecord.self, data)
    }
    public func saveCompanionRun(_ value: CompanionRunRecord) throws {
        var value = value
        if let old = try companionRun(value.turnID), old.stopRequested {
            value.stopRequested = true
            if ["cancelled", "completed"].contains(old.status) { value.status = old.status }
        }
        try database.execute("INSERT INTO companion_runs(id,payload) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload", [.text(value.turnID.uuidString), .blob(try Self.encode(value))])
    }
    public func pendingCompanionStops(connectionID: String) throws -> [CompanionRunRecord] {
        _ = try companionRun(UUID())
        return try database.execute("SELECT payload FROM companion_runs WHERE json_extract(CAST(payload AS TEXT),'$.stopRequested')=1 AND json_extract(CAST(payload AS TEXT),'$.connectionID')=? AND json_extract(CAST(payload AS TEXT),'$.status') NOT IN ('completed','cancelled') LIMIT 12", [.text(connectionID)])
            .map { try Self.decode(CompanionRunRecord.self, $0[0].data!) }
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
    private var outputOrder: [String: Int] = [:]
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
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = event["recordedAt"]?.stringValue.flatMap { formatter.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) } ?? Date()
        defer { cursor = sequence }
        switch event["type"]?.stringValue {
        case "response_begin":
            // Only the current, uncommitted response can be replaced after retry.
            if let index = activeIndex, messages[index].state != .complete { messages.removeSubrange(roundStart...) }
            activeIndex = nil; roundStart = messages.count; outputOrder = [:]
        case "text_delta":
            guard let text = event["text"]?.stringValue else { break }
            let index = ensureAssistant(sequence: sequence, date: date)
            let itemID = event["item_id"]?.stringValue ?? "current"
            let order = event["output_index"]?.numberValue.flatMap(Int.init(exactly:))
            let contentIndex = event["content_index"]?.numberValue.flatMap(Int.init(exactly:)) ?? 0
            let key = order.map { "\($0):\(itemID):\(contentIndex)" } ?? itemID
            if let part = messages[index].responseParts.firstIndex(where: { $0.id == key }) { messages[index].responseParts[part].text += text }
            else { messages[index].responseParts.append(ResponsePart(id: key, text: text, phase: event["phase"]?.stringValue)) }
            if let order { outputOrder[key] = order; sortParts(at: index) }
            messages[index].text = ResponsePresentation.text(in: messages[index].responseParts)
        case "web_activity":
            guard let item = event["item"], item["type"] == .string("web_search_call"),
                  let order = event["output_index"]?.numberValue.flatMap(Int.init(exactly:)), order >= 0,
                  let part = ResponsePresentation.parts(from: [order: item]).first else { break }
            let index = ensureAssistant(sequence: sequence, date: date)
            if let existing = messages[index].responseParts.firstIndex(where: { $0.id == part.id }) { messages[index].responseParts[existing] = part }
            else { messages[index].responseParts.append(part) }
            outputOrder[part.id] = order; sortParts(at: index)
        case "annotation":
            guard let annotation = event["annotation"], annotation["type"] == .string("url_citation"),
                  let url = annotation["url"]?.stringValue, let index = activeIndex,
                  let itemID = event["item_id"]?.stringValue,
                  let order = event["output_index"]?.numberValue.flatMap(Int.init(exactly:)) else { break }
            let contentIndex = event["content_index"]?.numberValue.flatMap(Int.init(exactly:)) ?? 0
            let key = "\(order):\(itemID):\(contentIndex)"
            if let part = messages[index].responseParts.firstIndex(where: { $0.id == key }),
               let citation = WebCitation(title: annotation["title"]?.stringValue ?? "", url: url,
                    startIndex: annotation["start_index"]?.numberValue.flatMap(Int.init(exactly:)),
                    endIndex: annotation["end_index"]?.numberValue.flatMap(Int.init(exactly:))),
               !messages[index].responseParts[part].citations.contains(where: { $0.url == citation.url }) {
                messages[index].responseParts[part].citations.append(citation)
            }
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
            let actualTool = call.name == "use_tool" ? call.arguments["name"]?.stringValue : call.name
            if actualTool == "publish_task_files" && result.succeeded {
                let files = (result.output["presented_files"]?.arrayValue ?? []).prefix(8).compactMap { $0["id"]?.stringValue.flatMap(UUID.init(uuidString:)) }
                if !files.isEmpty {
                    var published = Message(id: identifier(sequence, role: 2), role: .assistant,
                        text: String((result.output["caption"]?.stringValue ?? "").prefix(1000)), fileIDs: files,
                        providerID: providerID, containsHealthData: health || result.containsHealthData == true)
                    published.createdAt = date; messages.append(published)
                }
            }
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
    private mutating func sortParts(at index: Int) {
        messages[index].responseParts = messages[index].responseParts.enumerated().sorted {
            let left = outputOrder[$0.element.id] ?? Int.max, right = outputOrder[$1.element.id] ?? Int.max
            return left == right ? $0.offset < $1.offset : left < right
        }.map(\.element)
    }
}
