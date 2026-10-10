import Foundation

public enum WorkPhase: String, Codable, Sendable { case running, interrupted, completed, cancelled }
public struct WorkTurn: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var conversationID: UUID
    public var userMessageID: UUID
    public var backendID: String
    public var destination: String?
    public var goal: String
    public var phase: WorkPhase = .running
    public var reason: String?
    public var updatedAt: Date = Date()
    public var rounds = 0
    public var resumes = 0
    public var configuration: JSONValue = .object([:])
    public var plan: [JSONValue] = []
    public init(id: UUID, conversationID: UUID, userMessageID: UUID, backendID: String, destination: String? = nil, goal: String, configuration: JSONValue = .object([:])) {
        self.id = id; self.conversationID = conversationID; self.userMessageID = userMessageID
        self.backendID = backendID; self.destination = destination; self.goal = goal; self.configuration = configuration
    }
}
struct ToolOperation: Codable, Sendable {
    var key: String
    var conversationID: UUID
    var turnID: UUID
    var name: String
    var call: ToolCall
    var signature: String
    var localOnly: Bool = false
    var health: Bool = false
    var startedAt: Date = Date()
    var result: ToolResult?
}

extension LocalStore {
    private func ensureWorkJournal() throws {
        try database.execute("CREATE TABLE IF NOT EXISTS work_turns(id TEXT PRIMARY KEY,conversation_id TEXT NOT NULL,updated_at REAL NOT NULL,payload BLOB NOT NULL)")
        try database.execute("CREATE TABLE IF NOT EXISTS tool_operations(id TEXT PRIMARY KEY,conversation_id TEXT NOT NULL,turn_id TEXT NOT NULL,payload BLOB NOT NULL)")
    }
    public func saveWorkTurn(_ value: WorkTurn) throws {
        try ensureWorkJournal()
        var value = value; value.updatedAt = Date()
        guard value.goal.utf8.count <= 1600, value.rounds <= 12, value.resumes <= 3, try value.configuration.jsonString().utf8.count <= 16_384 else { throw AssistantError.invalidTool("The saved task exceeds its supported limits.") }
        try database.execute("INSERT INTO work_turns(id,conversation_id,updated_at,payload) VALUES(?,?,?,?) ON CONFLICT(id) DO UPDATE SET updated_at=excluded.updated_at,payload=excluded.payload", [.text(value.id.uuidString), .text(value.conversationID.uuidString), .real(value.updatedAt.timeIntervalSince1970), .blob(try Self.encode(value))])
    }
    public func workTurn(_ id: UUID) throws -> WorkTurn? {
        try ensureWorkJournal()
        guard let data = try database.execute("SELECT payload FROM work_turns WHERE id=?", [.text(id.uuidString)]).first?[0].data else { return nil }
        return try Self.decode(WorkTurn.self, data)
    }
    public func unfinishedWork() throws -> [WorkTurn] {
        try ensureWorkJournal()
        return try database.execute("""
            SELECT w.payload FROM work_turns w JOIN conversations c ON c.id=w.conversation_id
            JOIN messages m ON m.id=json_extract(CAST(w.payload AS TEXT),'$.userMessageID') AND m.conversation_id=c.id
            WHERE json_extract(CAST(w.payload AS TEXT),'$.phase') IN ('running','interrupted')
            AND json_extract(CAST(c.payload AS TEXT),'$.archivedAt') IS NULL ORDER BY w.updated_at DESC LIMIT 30
            """)
            .map { try Self.decode(WorkTurn.self, $0[0].data!) }
    }
    public func finishWork(_ id: UUID, phase: WorkPhase, reason: String? = nil) throws {
        guard var work = try workTurn(id) else { return }
        work.phase = phase; work.reason = reason.map { String($0.prefix(700)) }
        try saveWorkTurn(work)
    }
    func updateWorkPlan(_ turnID: UUID, steps: [JSONValue]) throws {
        guard var work = try workTurn(turnID) else { return }
        work.plan = steps; try saveWorkTurn(work)
    }
    func beginToolOperation(_ call: ToolCall, conversationID: UUID, turnID: UUID, localOnly: Bool = false, health: Bool = false) throws -> ToolOperation? {
        try ensureWorkJournal()
        let key = turnID.uuidString + ":" + call.id
        let signature = call.name + ":" + (try call.arguments.jsonString())
        if let payload = try database.execute("SELECT payload FROM tool_operations WHERE id=?", [.text(key)]).first?[0].data {
            let old = try Self.decode(ToolOperation.self, payload)
            guard old.signature == signature, old.conversationID == conversationID else { throw AssistantError.invalidTool("A repeated tool operation changed its request.") }
            return old
        }
        let value = ToolOperation(key: key, conversationID: conversationID, turnID: turnID, name: call.name, call: call, signature: signature, localOnly: localOnly, health: health)
        try database.execute("INSERT INTO tool_operations(id,conversation_id,turn_id,payload) VALUES(?,?,?,?)", [.text(key), .text(conversationID.uuidString), .text(turnID.uuidString), .blob(try Self.encode(value))])
        return nil
    }
    func toolOperations(_ id: UUID) throws -> [ToolOperation] {
        try ensureWorkJournal()
        return try database.execute("SELECT payload FROM tool_operations WHERE turn_id=? ORDER BY rowid LIMIT 24", [.text(id.uuidString)])
            .map { try Self.decode(ToolOperation.self, $0[0].data!) }
    }
    func finishToolOperation(_ call: ToolCall, turnID: UUID, result: ToolResult) throws {
        let key = turnID.uuidString + ":" + call.id
        guard let payload = try database.execute("SELECT payload FROM tool_operations WHERE id=?", [.text(key)]).first?[0].data else { throw AssistantError.invalidTool("The operation record is missing.") }
        var value = try Self.decode(ToolOperation.self, payload); value.result = result
        try database.execute("UPDATE tool_operations SET payload=? WHERE id=?", [.blob(try Self.encode(value)), .text(key)])
    }
    public func workEvidence(_ id: UUID, conversationID: UUID, remote: Bool, workspaceEnabled: Bool) throws -> JSONValue {
        guard let work = try workTurn(id) else { throw AssistantError.invalidTool("That task is unavailable.") }
        if work.conversationID == conversationID {
            let source = try message(work.userMessageID, in: conversationID)
            guard !remote || (!source.containsLocalOnlyContext && !source.containsHealthData) else { throw AssistantError.invalidTool("This saved task contains protected context.") }
        } else {
            guard workspaceEnabled else { throw AssistantError.invalidTool("Workspace access is disabled.") }
            _ = try sharedHistoryMessage(work.userMessageID, conversationID: work.conversationID, folderID: nil, remote: remote)
        }
        let operations = try database.execute("SELECT payload FROM tool_operations WHERE turn_id=? LIMIT 24", [.text(id.uuidString)])
            .map { try Self.decode(ToolOperation.self, $0[0].data!) }
        return .object(["task_id": .string(work.id.uuidString), "goal": .string(work.goal), "phase": .string(work.phase.rawValue), "plan": .array(work.plan),
            "reason": work.reason.map(JSONValue.string) ?? .null, "updated_at": .string(ISO8601DateFormatter().string(from: work.updatedAt)),
            "actions": .array(operations.map { op in .object(["tool": .string(op.name), "started_at": .string(ISO8601DateFormatter().string(from: op.startedAt)),
                "status": op.result?.output["status"] ?? .string(op.result == nil ? "outcome_unknown" : op.result!.succeeded ? "completed" : "failed"),
                "receipt_recorded": .bool(op.result != nil)]) }),
            "notice": .string("Phase describes the assistant turn, not proof that every real-world goal is complete. Plans are intentions; action receipts describe observed outcomes. An unfinished operation is not safe to repeat blindly.")])
    }
}
