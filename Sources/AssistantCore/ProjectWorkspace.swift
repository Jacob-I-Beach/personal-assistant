import Foundation

public struct ProjectWorkspace: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var sourceConversationID: UUID
    public var title: String
    public var goal: String
    public var status: String
    public var decisions: [String]
    public var questions: [String]
    public var outputIDs: [UUID]
    public var revision: Int
    public var updatedAt: Date
    public var containsLocalOnlyContext: Bool
    public var containsHealthData: Bool
    public var lastMutationConversationID: UUID?
    public var lastMutationCallID: String?
    public var needsContextRebuild: Bool?
    public var summary: JSONValue {
        .object(["project_id": .string(id.uuidString), "title": .string(title), "goal": .string(goal), "status": .string(status), "decisions": .array(decisions.map(JSONValue.string)), "open_questions": .array(questions.map(JSONValue.string)), "authoritative_output_ids": .array(outputIDs.map { .string($0.uuidString) }), "revision": .number(Double(revision)), "updated_at": .string(ISO8601DateFormatter().string(from: updatedAt)), "notice": .string("This is the maintained project record. Status and decisions are recorded context; individual action receipts establish external outcomes.")])
    }
}
extension LocalStore {
    public func projectWorkspaces() throws -> [ProjectWorkspace] {
        try database.execute("CREATE TABLE IF NOT EXISTS project_workspaces(id TEXT PRIMARY KEY,payload BLOB NOT NULL)")
        return try database.execute("SELECT payload FROM project_workspaces ORDER BY rowid DESC").map { try Self.decode(ProjectWorkspace.self, $0[0].data!) }
    }
    public func projectWorkspace(conversationID: UUID, remote: Bool) throws -> ProjectWorkspace? {
        let chat = try loadConversation(conversationID), scope = chat.folderID ?? chat.id
        guard var project = try projectWorkspaces().first(where: { $0.id == scope }) else { return nil }
        guard !remote || (!project.containsLocalOnlyContext && (!project.containsHealthData || (project.sourceConversationID == conversationID && chat.containsHealthData))) else { return nil }
        if (chat.invalidatedProjectRevisions[project.id.uuidString] ?? 0) >= project.revision {
            project.title = "Project context needs rebuilding"; project.goal = "An edited request removed the context used for this revision. Rebuild the summary from the current chat before using it. Saved outputs and external actions remain unchanged."
            project.decisions = []; project.questions = []; project.outputIDs = []; project.status = "waiting"; project.needsContextRebuild = true
        }
        return project
    }
    public func saveProjectWorkspace(_ project: ProjectWorkspace, expectedRevision: Int) throws {
        let existing = try projectWorkspaces().first(where: { $0.id == project.id })
        guard (existing?.revision ?? 0) == expectedRevision, project.revision == expectedRevision + 1 else { throw AssistantError.invalidTool("The project changed. Read its current revision before updating it.") }
        guard project.title.count <= 120, project.goal.count <= 1600, project.decisions.count <= 20, project.questions.count <= 20,
              (project.decisions + project.questions).allSatisfy({ $0.count <= 500 }), project.outputIDs.count <= 20,
              ["active", "waiting", "completed", "paused"].contains(project.status) else { throw AssistantError.invalidTool("Keep the project record concise and use a supported status.") }
        try database.execute("INSERT INTO project_workspaces(id,payload) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload", [.text(project.id.uuidString), .blob(try Self.encode(project))])
    }
}
public enum ProjectTools {
    private static let text: JSONValue = .object(["type": .string("string")])
    private static let list: JSONValue = .object(["type": .string("array"), "items": text, "maxItems": .number(20)])
    public static let definitions: [ToolDefinition] = [
        .init(name: "read_project", description: "Read this chat's maintained project record. Chats in the same user-selected topic folder share a project, subject to protected-context rules. It links the goal, current decisions, open questions and authoritative output IDs.", parameters: .object(["type": .string("object"), "properties": .object([:]), "required": .array([]), "additionalProperties": .bool(false)])),
        .init(name: "update_project", description: "Maintain this chat or topic folder's project record with the current goal, decisions, unresolved questions and authoritative output IDs. Read it first; revision 0 creates a new record. Preserve still-valid decisions. Project completion is a summary, not proof of an external action. Link only known outputs available in this workspace.", parameters: .object(["type": .string("object"), "additionalProperties": .bool(false), "required": .array(["title", "goal", "status", "decisions", "open_questions", "output_ids", "expected_revision"].map(JSONValue.string)), "properties": .object([
            "title": text, "goal": text, "status": .object(["type": .string("string"), "enum": .array(["active", "waiting", "completed", "paused"].map(JSONValue.string))]), "decisions": list, "open_questions": list, "output_ids": list, "expected_revision": .object(["type": .string("integer"), "minimum": .number(0)])
        ])]))
    ]
    public static func execute(_ call: ToolCall, store: LocalStore, conversationID: UUID, workspace: Bool, remote: Bool, localOnly: Bool, health: Bool) async throws -> ToolResult {
        let chat = try await store.loadConversation(conversationID)
        let current = try await store.projectWorkspace(conversationID: conversationID, remote: remote)
        var result: ToolResult
        if call.name == "read_project" { result = ToolResult(callID: call.id, name: call.name, succeeded: true, output: current?.summary ?? .object(["status": .string("no_project_record"), "revision": .number(0)])) }
        else {
            let rawIDs = call.arguments["output_ids"]?.arrayValue?.compactMap(\.stringValue) ?? [], ids = rawIDs.compactMap(UUID.init(uuidString:))
            let artifacts = try await store.readableArtifacts(conversationID: conversationID, workspace: workspace, remote: remote)
            let files = try await store.readableFiles(attached: chat.attachedFileIDs, workspace: workspace, remote: remote, conversationID: conversationID)
            let allowed = Set(artifacts.map(\.id) + files.map(\.id))
            guard ids.count == rawIDs.count, Set(ids).isSubset(of: allowed) else { throw AssistantError.invalidTool("Use output IDs already available in this project.") }
            let revision = try ToolArguments.integer(call.arguments["expected_revision"], field: "expected_revision")
            var project = ProjectWorkspace(id: chat.folderID ?? chat.id, sourceConversationID: current?.sourceConversationID ?? chat.id, title: call.arguments["title"]?.stringValue ?? "Project", goal: call.arguments["goal"]?.stringValue ?? "", status: call.arguments["status"]?.stringValue ?? "active", decisions: call.arguments["decisions"]?.arrayValue?.compactMap(\.stringValue) ?? [], questions: call.arguments["open_questions"]?.arrayValue?.compactMap(\.stringValue) ?? [], outputIDs: ids, revision: revision + 1, updatedAt: Date(), containsLocalOnlyContext: localOnly || current?.containsLocalOnlyContext == true, containsHealthData: health || current?.containsHealthData == true)
            project.containsLocalOnlyContext = project.containsLocalOnlyContext || artifacts.contains { ids.contains($0.id) && $0.containsLocalOnlyContext }
            project.lastMutationConversationID = chat.id; project.lastMutationCallID = call.id
            project.containsHealthData = project.containsHealthData || artifacts.contains { ids.contains($0.id) && $0.containsHealthData } || files.contains { ids.contains($0.id) && $0.containsHealthData }
            try await store.saveProjectWorkspace(project, expectedRevision: revision)
            result = ToolResult(callID: call.id, name: call.name, succeeded: true, output: project.summary)
            result.containsLocalOnlyContext = project.containsLocalOnlyContext
            result.containsHealthData = project.containsHealthData
        }
        result.containsLocalOnlyContext = result.containsLocalOnlyContext == true || localOnly || current?.containsLocalOnlyContext == true
        result.containsHealthData = result.containsHealthData == true || health || current?.containsHealthData == true
        return result
    }
}
