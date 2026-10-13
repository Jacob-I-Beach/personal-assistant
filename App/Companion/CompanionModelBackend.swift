import Foundation
import UniformTypeIdentifiers
import AssistantCore

struct CompanionModelBackend: RemoteTaskBackend {
    let connection: CompanionConnection
    let client: CompanionClient
    let wire: NetworkModelBackend
    let store: LocalStore
    var allowJobRestart = false
    var onJobAccepted: (@Sendable (String) async -> Void)?
    var id: String { "companion:" + connection.serverID + ":" + connection.profileID + ":" + wire.id }
    var networkDestination: String? { connection.destination }
    var contextLimits: ContextLimits { wire.contextLimits }
    var supportsFileInputs: Bool { true }
    // Optional naming remains a short request. User work always uses runTask.
    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        AsyncThrowingStream { output in
            let task = Task {
                do {
                    guard request.isMetadata, !request.containsLocalOnlyContext else { throw AssistantError.networkNotAuthorized }
                    let result = try await client.json("/v1/metadata", method: "POST", body: .object(["profile_id": .string(connection.profileID), "body": try wire.responsesBody(request)]))
                    guard let text = result["text"]?.stringValue, !text.isEmpty else { throw AssistantError.incompleteResponse }
                    output.yield(.textDelta(text)); output.yield(.completed); output.finish()
                } catch { output.finish(throwing: error) }
            }
            output.onTermination = { @Sendable _ in task.cancel() }
        }
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
            var fields: [String: JSONValue] = [
                "request_key": .string(identity.turnID.uuidString), "turn_id": .string(identity.turnID.uuidString),
                "conversation_id": .string(identity.conversationID.uuidString), "profile_id": .string(connection.profileID),
                "title": .string(String((request.messages.last(where: { $0.message.isRequest })?.message.text ?? "Assistant task").prefix(120))),
                "contains_health_data": .bool(identity.containsHealthData), "body": try wire.responsesBody(request, includeFileContents: false),
                "start_when_ready": .bool(true),
                "expected_file_ids": .array(Array(Set(request.messages.flatMap(\.files).compactMap(\.id))).map { .string($0.uuidString) }),
                "catalog": .array(request.toolCatalog.map { .object(["name": .string($0.name), "description": .string($0.description), "parameters": $0.parameters]) }),
                "limits": .object(["maximum_seconds": .number(3600), "maximum_tool_calls": .number(40), "context_text_bytes": .number(Double(contextLimits.maximumTextBytes))])
            ]
            if let workspace = try await store.computerToolWorkspace(identity.turnID), workspace["destination"] == connection.destination, let job = workspace["job_id"] { fields["source_tool_session_id"] = .string(job) }
            if let context = request.serverContext { fields["server_context"] = context }
            let payload = JSONValue.object(fields)
            record = CompanionRunRecord(turnID: identity.turnID, connectionID: connection.destination, payload: payload)
            // Save before POST: if its reply is lost, the original key and bytes
            // recover that job instead of silently submitting different work.
            try await store.saveCompanionRun(record)
        }
        if record.jobID == nil {
            let value = try await client.json("/v1/jobs", method: "POST", body: record.payload)
            guard let id = value["id"]?.stringValue, UUID(uuidString: id) != nil else { throw AssistantError.provider("The computer did not return a saved task identifier.") }
            record.jobID = id; record.status = value["status"]?.stringValue ?? "queued"
            // The original request is needed only until the durable job ID is
            // acknowledged. Avoid retaining another base64 copy of attachments.
            if var payload = record.payload.objectValue, var body = payload["body"]?.objectValue {
                body["input"] = .array([]); payload["body"] = .object(body); record.payload = .object(payload)
            }
            try await store.saveCompanionRun(record)
        }
        let jobID = record.jobID!, path = "/v1/jobs/" + jobID
        await onJobAccepted?(jobID)
        if record.stopRequested {
            _ = try await client.json(path + "/cancel", method: "POST", body: .object([:]))
            throw CancellationError()
        }
        let job = try await observe(path, output: output)
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
        if status == "queued" || (allowJobRestart && ["failed", "interrupted"].contains(status)) {
            _ = try await client.json(path + "/start", method: "POST", body: .object(["context_text_bytes": .number(Double(contextLimits.maximumTextBytes))]))
        }
        var transcript = CompanionTranscript(jobID: UUID(uuidString: jobID)!, providerID: id, health: identity.containsHealthData)
        var pending: [String: ToolCall] = [:], answered = Set<String>()
        var latestActivity = "Continuing your reply"
        var replay = CompanionReplayGate(lastSyncedCursor: record.lastSyncedCursor)
        var pendingReceipts: [(ToolCall, ToolResult)] = []
        while true {
            try Task.checkCancellation()
            let batch = try await observe(path + "/events?after=\(transcript.cursor)&wait_ms=25000", output: output)
            let events = batch["events"]?.arrayValue ?? []
            var observedActivity: String?
            for event in events {
                if event["type"] == .string("phone_request"), let call = event["call"] {
                    let value = try JSONDecoder().decode(ToolCall.self, from: JSONEncoder().encode(call)); pending[value.id] = value
                }
                if let (call, result) = try transcript.apply(event) {
                    answered.insert(call.id); pending.removeValue(forKey: call.id)
                    pendingReceipts.append((call, result))
                }
                if event["type"] == .string("activity"), let title = event["title"]?.stringValue { observedActivity = title }
                if event["type"] == .string("status"), let title = event["text"]?.stringValue,
                   !["completed", "failed", "cancelled", "interrupted"].contains(event["status"]?.stringValue ?? "") { observedActivity = title }
            }
            // Persist one coherent projection per batch, including exact action
            // receipts and visible questions/answers, before moving the cursor.
            let snapshotCursor = Int(batch["job"]?["cursor"]?.numberValue ?? 0)
            let canPublish = replay.canPublish(cursor: transcript.cursor, snapshotCursor: snapshotCursor)
            if !events.isEmpty && canPublish {
                try await request.commitRemoteTranscript?(transcript.messages, pendingReceipts.map(\.1))
                for (call, result) in pendingReceipts { output.yield(.receipt(call, result)) }
                pendingReceipts.removeAll()
                record.lastSyncedCursor = transcript.cursor
                if let observedActivity { latestActivity = observedActivity; output.yield(.activity(observedActivity)) }
                output.yield(.transportProgress((try? JSONEncoder().encode(events).count) ?? 0))
                output.yield(.transcript(transcript.messages))
            } else if canPublish && batch["job"]?["status"] == .string("running") {
                // A successful long poll confirms the connection, not more
                // completed work. Keep status fresh without inventing progress.
                output.yield(.activity(latestActivity))
            }
            record.status = batch["job"]?["status"]?.stringValue ?? record.status
            try await store.saveCompanionRun(record)
            let caughtUp = transcript.cursor >= snapshotCursor
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
                if events.last(where: { $0["type"] == .string("status") })?["error"]?["code"] == .string("context_limit") { throw AssistantError.contextCapacity }
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
    private func observe(_ path: String, output: AsyncThrowingStream<RemoteTaskEvent, any Error>.Continuation) async throws -> JSONValue {
        var retries = 0
        while true {
            try Task.checkCancellation()
            do { return try await client.json(path) }
            catch {
                try Task.checkCancellation()
                guard CompanionObservationPolicy.shouldRetry(error) else { throw error }
                retries = min(5, retries + 1)
                output.yield(.activity("Reconnecting to your saved task"))
                try await Task.sleep(for: .seconds(retries * 2))
            }
        }
    }
    private func importOutputs(path: String, identity: ModelWorkIdentity) async throws -> [UUID] {
        let catalog = try await client.json(path + "/files")
        var imported: [UUID] = []
        for entry in catalog["files"]?.arrayValue ?? [] {
            guard entry["role"] == .string("artifact"), let rawID = entry["id"]?.stringValue, let id = UUID(uuidString: rawID),
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
