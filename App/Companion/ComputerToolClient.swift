import Foundation
import UniformTypeIdentifiers
import AssistantCore

enum ComputerTools {
    static let definitions: [ToolDefinition] = {
        guard let url = Bundle.main.url(forResource: "ComputerToolCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        let values = (try? JSONDecoder().decode([JSONValue].self, from: data)) ?? []
        return values.compactMap { value in
            guard let name = value["name"]?.stringValue, let description = value["description"]?.stringValue, let parameters = value["parameters"] else { return nil }
            return ToolDefinition(name: name, description: description, parameters: parameters)
        }
    }()
    static var names: Set<String> { Set(definitions.map(\.name)) }
}

extension AppModel {
    func computerToolWorkspace(turn: UUID, conversationID: UUID) async throws -> (CompanionClient, String) {
        guard !settings.localOnly, settings.useComputer, let connection = settings.companion, let store else { throw AssistantError.invalidTool("Connect your computer in Connections to use this tool.") }
        let client = try CompanionClient(baseURL: connection.baseURL, fingerprint: connection.certificateSHA256, token: CredentialStore.read(account: connection.credentialAccount))
        if let run = try await store.companionRun(turn), let id = run.jobID {
            guard run.connectionID == connection.destination else { throw AssistantError.networkNotAuthorized }
            return (client, id)
        }
        if let workspace = try await store.computerToolWorkspace(turn) {
            guard workspace["destination"] == connection.destination, let id = workspace["job_id"] else { throw AssistantError.networkNotAuthorized }
            return (client, id)
        }
        let value = try await client.json("/v1/tool-sessions", method: "POST", body: .object(["request_key": .string(turn.uuidString), "conversation_id": .string(conversationID.uuidString)]))
        guard let id = value["id"]?.stringValue, UUID(uuidString: id) != nil else { throw AssistantError.provider("The computer did not open the tool workspace.") }
        try await store.saveComputerToolWorkspace(turn, jobID: id, destination: connection.destination)
        return (client, id)
    }
    func executeComputerTool(_ call: ToolCall, conversationID: UUID) async throws -> ToolResult {
        guard let turn = ToolExecutionContext.current?.turnID else { throw AssistantError.invalidTool("This computer action needs an active task.") }
        let (client, job) = try await computerToolWorkspace(turn: turn, conversationID: conversationID)
        // Only explicit file handles already authorized to this chat are transferred.
        var requested = call.arguments["file_ids"]?.arrayValue?.compactMap(\.stringValue) ?? []
        if let id = call.arguments["file_id"]?.stringValue { requested.append(id) }
        let existing = try await client.json("/v1/jobs/" + job + "/files")["files"]?.arrayValue ?? []
        for raw in Set(requested) where !existing.contains(where: { $0["id"] == .string(raw) }) {
            _ = try await transferFileToComputer(ToolCall(id: call.id + "-input", name: ComputerFileTools.transfer.name, arguments: .object(["kind": .string("file"), "id": .string(raw)])), conversationID: conversationID)
        }
        let value = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(call))
        var operation = try await client.json("/v1/jobs/" + job + "/execute-tool", method: "POST", body: value)
        while operation["result"] == nil || operation["result"] == .null {
            try Task.checkCancellation()
            if operation["status"] == .string("outcome_unknown") { throw AssistantError.provider("This tool started earlier without a final receipt. Inspect the saved output before repeating it.") }
            try await Task.sleep(for: .seconds(1))
            operation = try await client.json("/v1/jobs/" + job + "/operations/" + call.id)
        }
        let raw = operation["result"]!
        guard let succeeded = raw["succeeded"]?.boolValue else { throw AssistantError.provider("The computer returned an incomplete tool receipt.") }
        var result = ToolResult(callID: call.id, name: call.name, succeeded: succeeded, output: raw["output"] ?? .null)
        result.containsHealthData = raw["containsHealthData"]?.boolValue
        if let time = raw["completedAt"]?.stringValue {
            let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: time) ?? ISO8601DateFormatter().date(from: time) { result.completedAt = date }
        }
        let files = try await importComputerFiles(client: client, jobID: job, conversationID: conversationID, health: result.containsHealthData == true)
        if var output = result.output.objectValue { output["library_files"] = .array(files.map { .string($0.uuidString) }); result.output = .object(output) }
        return result
    }
    func importComputerFiles(client: CompanionClient, jobID: String, conversationID: UUID, health: Bool) async throws -> [UUID] {
        guard let store else { return [] }
        let catalog = try await client.json("/v1/jobs/" + jobID + "/files")
        var ids: [UUID] = []
        for item in catalog["files"]?.arrayValue ?? [] where item["role"] == .string("artifact") || item["role"] == .string("inspection") {
            guard let raw = item["id"]?.stringValue, let id = UUID(uuidString: raw), let name = item["filename"]?.stringValue else { continue }
            ids.append(id)
            if (try? await store.workspaceFile(id)) != nil { continue }
            let data = try await client.data("/v1/jobs/" + jobID + "/files/" + raw)
            let type = UTType(filenameExtension: URL(fileURLWithPath: name).pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            let text = type.hasPrefix("text/") || ["application/json", "image/svg+xml"].contains(type) ? String(data: data, encoding: .utf8) ?? "" : ""
            try await store.saveWorkspaceFile(WorkspaceFile(id: id, filename: name, mediaType: type, byteCount: data.count, text: String(text.prefix(200_000)), extractionNote: "Created with your computer tools; available in this chat and Library.", conversationID: conversationID, containsHealthData: health || item["contains_health_data"] == .bool(true)), data: data)
        }
        return ids
    }
}
