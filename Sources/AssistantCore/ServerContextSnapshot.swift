import Foundation

/// Retrieval data sent to the user's task server, separately from model input.
/// The same connected-model permission filters apply; opaque reasoning and
/// on-device-only material never enter this snapshot.
public enum ServerContextSnapshot {
    public static func make(conversation: Conversation, memories: [SavedMemory]) -> JSONValue {
        let formatter = ISO8601DateFormatter()
        var remaining = 384_000
        var history: [JSONValue] = []
        for message in conversation.messages.reversed().filter({ !$0.containsLocalOnlyContext }).prefix(100) {
            let text = String(message.text.prefix(16_000))
            guard text.utf8.count <= remaining else { break }; remaining -= text.utf8.count
            history.append(.object(["message_id": .string(message.id.uuidString), "role": .string(message.role.rawValue),
                "created_at": .string(formatter.string(from: message.createdAt)), "text": .string(text),
                "total_characters": .number(Double(message.text.count)), "complete": .bool(text.count == message.text.count)]))
        }
        var notes: [JSONValue] = []
        for note in MemoryContext.eligible(memories, conversationID: conversation.id, remote: true).prefix(64) {
            let text = String(note.text.prefix(16_000))
            guard text.utf8.count <= remaining else { break }; remaining -= text.utf8.count
            notes.append(.object(["memory_id": .string(note.id.uuidString), "title": .string(note.title), "text": .string(text),
                "revision": .number(Double(note.revision)), "basis": .string(note.basis.rawValue), "status": .string(note.status.rawValue),
                "kind": .string(note.kind.rawValue), "source": .string(note.source), "updated_at": .string(formatter.string(from: note.updatedAt)),
                "total_characters": .number(Double(note.text.count)), "complete": .bool(text.count == note.text.count)]))
        }
        return .object(["conversation_id": .string(conversation.id.uuidString), "captured_at": .string(formatter.string(from: Date())),
            "history": .array(Array(history.reversed())), "memories": .array(notes),
            "coverage": .string("A bounded snapshot of this chat and permitted memory at Send. Other chats, unshared material and later changes require their own access.")])
    }
}
