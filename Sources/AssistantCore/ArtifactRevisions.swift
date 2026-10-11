import Foundation

extension LocalStore {
    private func prepareArtifactHistory() throws { try database.execute("CREATE TABLE IF NOT EXISTS artifact_history(id TEXT NOT NULL,revision INTEGER NOT NULL,payload BLOB NOT NULL,PRIMARY KEY(id,revision))") }
    public func artifactHistory(_ id: UUID) throws -> [ArtifactRecord] {
        try prepareArtifactHistory()
        return try database.execute("SELECT payload FROM artifact_history WHERE id=? ORDER BY revision DESC", [.text(id.uuidString)])
            .map { try Self.decode(ArtifactRecord.self, $0[0].data!) }
    }
    public func reviseArtifact(id: UUID, expectedRevision: Int, content: String, sourceCallID: String? = nil, localOnly: Bool = false, health: Bool = false) throws -> ArtifactRecord {
        guard let original = try artifacts().first(where: { $0.id == id }), original.revision == expectedRevision else { throw AssistantError.invalidTool("This document changed. Read its current revision before saving your changes.") }
        guard content.utf8.count <= 2 * 1024 * 1024 else { throw AssistantError.invalidTool("The revised document exceeds 2 MB.") }
        try prepareArtifactHistory()
        var revised = original
        revised.content = content; revised.revision += 1
        revised.containsLocalOnlyContext = revised.containsLocalOnlyContext || localOnly
        revised.containsHealthData = revised.containsHealthData || health
        // Preserve the original creation link used by existing chat cards.
        try database.execute("BEGIN IMMEDIATE")
        do {
            try database.execute("INSERT INTO artifact_history(id,revision,payload) VALUES(?,?,?)", [.text(id.uuidString), .integer(Int64(original.revision)), .blob(try Self.encode(original))])
            try database.execute("UPDATE artifacts SET payload=? WHERE id=?", [.blob(try Self.encode(revised)), .text(id.uuidString)])
            try database.execute("COMMIT")
        } catch { try? database.execute("ROLLBACK"); throw error }
        return revised
    }
}

public enum ArtifactRevisionTools {
    private static let string: JSONValue = .object(["type": .string("string")])
    private static let revision: JSONValue = .object(["type": .string("integer"), "minimum": .number(1)])
    public static let definitions: [ToolDefinition] = [
        .init(name: "update_artifact", description: "Update an existing text document in this conversation, preserving its ID and prior revisions. Requires its exact current revision. Supply either full replacement content with an empty patches list, or an empty content string and exact text patches. Each patch must match once; stale or ambiguous edits are rejected. Saving does not verify factual correctness.", parameters: .object(["type": .string("object"), "additionalProperties": .bool(false), "required": .array(["artifact_id", "expected_revision", "content", "patches"].map(JSONValue.string)), "properties": .object([
            "artifact_id": string, "expected_revision": revision, "content": string,
            "patches": .object(["type": .string("array"), "maxItems": .number(30), "items": .object(["type": .string("object"), "additionalProperties": .bool(false), "required": .array([.string("before"), .string("after")]), "properties": .object(["before": string, "after": string])])])
        ])])),
        .init(name: "read_artifact_revision", description: "Read the current or a saved earlier revision of a document available to this chat. Revision 0 selects current. Returns a bounded text excerpt and exact revision for updates.", parameters: .object(["type": .string("object"), "additionalProperties": .bool(false), "required": .array(["artifact_id", "revision", "offset"].map(JSONValue.string)), "properties": .object(["artifact_id": string, "revision": .object(["type": .string("integer"), "minimum": .number(0)]), "offset": .object(["type": .string("integer"), "minimum": .number(0)])])]))
    ]
    public static func execute(_ call: ToolCall, store: LocalStore, conversationID: UUID, remote: Bool, localOnly: Bool, health: Bool) async throws -> ToolResult {
        guard let id = call.arguments["artifact_id"]?.stringValue.flatMap(UUID.init(uuidString:)),
              let current = try await store.readableArtifacts(conversationID: conversationID, workspace: false, remote: remote).first(where: { $0.id == id }) else { throw AssistantError.invalidTool("This document is not available in the current chat.") }
        let output: JSONValue
        if call.name == "update_artifact" {
            let patches = call.arguments["patches"]?.arrayValue ?? []
            var content = call.arguments["content"]?.stringValue ?? ""
            if !patches.isEmpty {
                guard content.isEmpty else { throw AssistantError.invalidTool("Choose complete replacement or exact patches, not both.") }
                content = current.content
                for patch in patches {
                    guard let before = patch["before"]?.stringValue, !before.isEmpty, let after = patch["after"]?.stringValue,
                          content.components(separatedBy: before).count == 2 else { throw AssistantError.invalidTool("Each patch must match exactly once in the current document. Read it again before editing.") }
                    content = content.replacingOccurrences(of: before, with: after)
                }
            }
            let saved = try await store.reviseArtifact(id: id, expectedRevision: Int(call.arguments["expected_revision"]?.numberValue ?? 0), content: content, sourceCallID: call.id, localOnly: localOnly, health: health)
            let copy = try await store.refreshPublishedOutput(id: saved.id, filename: saved.filename, previous: Data(current.content.utf8), replacement: Data(saved.content.utf8), conversationID: conversationID)
            output = .object(["artifact_id": .string(id.uuidString), "filename": .string(saved.filename), "revision": .number(Double(saved.revision)), "status": .string("saved"), "history_preserved": .bool(true), "export_status": .string(copy?.status ?? "stored_in_library")])
        } else {
            let requested = Int(call.arguments["revision"]?.numberValue ?? 0), offset = Int(call.arguments["offset"]?.numberValue ?? 0)
            let record: ArtifactRecord
            if requested == 0 || requested == current.revision { record = current }
            else { guard let earlier = try await store.artifactHistory(id).first(where: { $0.revision == requested }) else { throw AssistantError.invalidTool("That revision is unavailable.") }; record = earlier }
            guard offset <= record.content.count else { throw AssistantError.invalidTool("The offset is outside this document.") }
            let text = String(record.content.dropFirst(offset).prefix(12_000))
            output = .object(["artifact_id": .string(id.uuidString), "filename": .string(record.filename), "revision": .number(Double(record.revision)), "current_revision": .number(Double(current.revision)), "text": .string(text), "next_offset": .number(Double(offset + text.count)), "total_characters": .number(Double(record.content.count))])
        }
        var result = ToolResult(callID: call.id, name: call.name, succeeded: true, output: output)
        result.containsHealthData = health || current.containsHealthData; result.containsLocalOnlyContext = localOnly || current.containsLocalOnlyContext
        return result
    }
}
