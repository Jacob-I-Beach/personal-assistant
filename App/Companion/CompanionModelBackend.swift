import Foundation
import UniformTypeIdentifiers
import AssistantCore

struct CompanionModelBackend: RemoteTaskBackend {
    let connection: CompanionConnection
    let client: CompanionClient
    let wire: NetworkModelBackend
    let store: LocalStore
    var id: String { "companion:" + connection.serverID + ":" + connection.profileID + ":" + wire.id }
    var networkDestination: String? { connection.destination }
    var contextLimits: ContextLimits { wire.contextLimits }
    var supportsFileInputs: Bool { true }
    // Metadata calls remain short, explicit jobs too. Ordinary assistant turns
    // use runTask, which has a persistent turn identity and resumable transcript.
    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        AsyncThrowingStream { $0.finish(throwing: AssistantError.provider("Computer task metadata is generated with the task itself.")) }
    }
    func runTask(_ request: ModelRequest) -> AsyncThrowingStream<RemoteTaskEvent, any Error> {
        AsyncThrowingStream { output in
            let task = Task {
                do { try await follow(request, output: output); output.finish() }
                catch { output.finish(throwing: error) }
            }
            output.onTermination = { @Sendable _ in task.cancel() }
        }
    }
    private func follow(_ request: ModelRequest, output: AsyncThrowingStream<RemoteTaskEvent, any Error>.Continuation) async throws {
        guard let identity = request.workIdentity, !request.containsLocalOnlyContext else { throw AssistantError.networkNotAuthorized }
        var record: CompanionRunRecord
        if let saved = try await store.companionRun(identity.turnID) {
            guard saved.connectionID == connection.destination else { throw AssistantError.provider("Reconnect the computer and account originally used for this task.") }
            record = saved
        } else {
            let payload: JSONValue = .object([
                "request_key": .string(identity.turnID.uuidString), "turn_id": .string(identity.turnID.uuidString),
                "conversation_id": .string(identity.conversationID.uuidString), "profile_id": .string(connection.profileID),
                "title": .string(String((request.messages.last(where: { $0.message.isRequest })?.message.text ?? "Assistant task").prefix(120))),
                "contains_health_data": .bool(identity.containsHealthData), "body": try wire.responsesBody(request),
                "catalog": .array(request.toolCatalog.map { .object(["name": .string($0.name), "description": .string($0.description), "parameters": $0.parameters]) }),
                "limits": .object(["maximum_seconds": .number(3600), "maximum_tool_calls": .number(40)])
            ])
            record = CompanionRunRecord(turnID: identity.turnID, connectionID: connection.destination, payload: payload)
            // Save before POST: if its reply is lost, the original key and bytes
            // recover that job instead of silently submitting different work.
            try await store.saveCompanionRun(record)
        }
        if record.jobID == nil {
            let value = try await client.json("/v1/jobs", method: "POST", body: record.payload)
            guard let id = value["id"]?.stringValue, UUID(uuidString: id) != nil else { throw AssistantError.provider("The computer did not return a saved task identifier.") }
            record.jobID = id; record.status = value["status"]?.stringValue ?? "queued"
            try await store.saveCompanionRun(record)
        }
        let jobID = record.jobID!, path = "/v1/jobs/" + jobID
        if record.stopRequested {
            _ = try await client.json(path + "/cancel", method: "POST", body: .object([:]))
            throw CancellationError()
        }
        let job = try await client.json(path)
        let status = job["status"]?.stringValue ?? "unknown"
        if status == "queued" {
            for file in request.messages.flatMap(\.files) {
                guard let id = file.id else { continue }
                _ = try await client.json(path + "/files", method: "POST", body: .object([
                    "id": .string(id.uuidString), "filename": .string(file.filename), "data_base64": .string(file.data.base64EncodedString()),
                    "contains_health_data": .bool(file.containsHealthData)
                ]))
            }
        }
        if ["queued", "failed", "interrupted"].contains(status) {
            _ = try await client.json(path + "/start", method: "POST", body: .object([:]))
        }
        var transcript = CompanionTranscript(jobID: UUID(uuidString: jobID)!, providerID: id, health: identity.containsHealthData)
        var pending: [String: ToolCall] = [:], answered = Set<String>(), retries = 0
        while true {
            try Task.checkCancellation()
            let batch: JSONValue
            do { batch = try await client.json(path + "/events?after=\(transcript.cursor)&wait_ms=25000"); retries = 0 }
            catch {
                try Task.checkCancellation(); retries += 1
                guard retries <= 5 else { throw AssistantError.provider("Your computer may still be working. Reconnect to retrieve the same task; completed actions will not be repeated.") }
                output.yield(.activity("Reconnecting to your computer \(retries)/5"))
                try await Task.sleep(for: .seconds(min(10, retries * 2))); continue
            }
            let events = batch["events"]?.arrayValue ?? []
            var receipts: [ToolResult] = []
            for event in events {
                if event["type"] == .string("phone_request"), let call = event["call"] {
                    let value = try JSONDecoder().decode(ToolCall.self, from: JSONEncoder().encode(call)); pending[value.id] = value
                }
                if let (call, result) = try transcript.apply(event) {
                    answered.insert(call.id); pending.removeValue(forKey: call.id)
                    receipts.append(result)
                    output.yield(.receipt(call, result))
                }
                if event["type"] == .string("activity"), let title = event["title"]?.stringValue { output.yield(.activity(title)) }
                if event["type"] == .string("status"), let title = event["text"]?.stringValue { output.yield(.activity(title)) }
            }
            // Persist one coherent projection per batch, including exact action
            // receipts and visible questions/answers, before moving the cursor.
            if !events.isEmpty {
                try await request.commitRemoteTranscript?(transcript.messages, receipts)
                output.yield(.transcript(transcript.messages))
            }
            record.status = batch["job"]?["status"]?.stringValue ?? record.status
            try await store.saveCompanionRun(record)
            let caughtUp = transcript.cursor >= Int(batch["job"]?["cursor"]?.numberValue ?? 0)
            if !caughtUp { continue }
            if record.status == "completed" {
                let files = try await importOutputs(path: path, identity: identity)
                var messages = transcript.messages
                if let index = messages.lastIndex(where: { $0.role == .assistant }), !files.isEmpty {
                    messages[index].fileIDs = files
                    try await request.commitRemoteTranscript?(messages, [])
                    output.yield(.transcript(messages))
                }
                output.yield(.completed); return
            }
            if record.status == "cancelled" { throw CancellationError() }
            if ["failed", "interrupted"].contains(record.status) {
                _ = try await importOutputs(path: path, identity: identity)
                throw AssistantError.provider(events.last(where: { $0["type"] == .string("status") })?["text"]?.stringValue ?? "Your computer saved this task. Continue when ready.")
            }
            for call in pending.values.sorted(by: { $0.id < $1.id }) where !answered.contains(call.id) {
                let operation = try await client.json(path + "/operations/" + call.id)
                if operation["result"] != nil && operation["result"] != .null { answered.insert(call.id); continue }
                guard let execute = request.toolExecutor else { throw AssistantError.invalidTool("The phone action handler is unavailable.") }
                let result = try await execute(call)
                guard result.containsLocalOnlyContext != true else { throw AssistantError.networkNotAuthorized }
                let json = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(result))
                _ = try await client.json(path + "/operations/" + call.id + "/result", method: "POST", body: json)
                answered.insert(call.id)
            }
        }
    }
    private func importOutputs(path: String, identity: ModelWorkIdentity) async throws -> [UUID] {
        let catalog = try await client.json(path + "/files")
        var imported: [UUID] = []
        for entry in catalog["files"]?.arrayValue ?? [] {
            guard ["artifact", "inspection"].contains(entry["role"]?.stringValue ?? ""), let rawID = entry["id"]?.stringValue, let id = UUID(uuidString: rawID),
                  let name = entry["filename"]?.stringValue else { continue }
            imported.append(id)
            if (try? await store.workspaceFile(id)) != nil { continue }
            let data = try await client.data(path + "/files/" + rawID)
            let type = UTType(filenameExtension: URL(fileURLWithPath: name).pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            let text = type.hasPrefix("text/") || ["application/json", "image/svg+xml"].contains(type) ? String(data: data, encoding: .utf8) ?? "" : ""
            let file = WorkspaceFile(id: id, filename: name, mediaType: type, byteCount: data.count, text: String(text.prefix(200_000)),
                extractionNote: "Created on your connected computer. The original is available for preview and sharing.", conversationID: identity.conversationID,
                containsHealthData: identity.containsHealthData || entry["contains_health_data"] == .bool(true))
            try await store.saveWorkspaceFile(file, data: data)
        }
        return imported
    }
}
