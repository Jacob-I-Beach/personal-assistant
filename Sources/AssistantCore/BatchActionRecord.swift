import Foundation

extension LocalStore {
    public func batchAction(_ id: String, conversationID: UUID) throws -> JSONValue? {
        guard id.utf8.count <= 220 else { throw AssistantError.invalidTool("Invalid batch identifier.") }
        guard let text = try database.execute("SELECT value FROM metadata WHERE key=?", [.text("action-batch:" + id)]).first?[0].text else { return nil }
        let value = try JSONValue.parse(text)
        guard value["conversation_id"] == .string(conversationID.uuidString) else { throw AssistantError.invalidTool("This batch belongs to a different chat.") }
        return value
    }
    public func saveBatchAction(_ id: String, conversationID: UUID, steps: [JSONValue]) throws {
        guard id.utf8.count <= 220, (1...8).contains(steps.count) else { throw AssistantError.invalidTool("Use a batch of one to eight changes.") }
        _ = try batchAction(id, conversationID: conversationID)
        let value: JSONValue = .object(["batch_id": .string(id), "conversation_id": .string(conversationID.uuidString), "items": .array(steps), "notice": .string("Each item has its own outcome. These changes are not atomic across apps or sources. A started item without a receipt has an unknown outcome and must not be repeated blindly.")])
        try database.execute("INSERT INTO metadata(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", [.text("action-batch:" + id), .text(try value.jsonString())])
    }
}
