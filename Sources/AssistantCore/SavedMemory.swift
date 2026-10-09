import Foundation

public struct SavedMemory: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var text: String
    public var conversationID: UUID?
    public var allowsConnectedModels: Bool
    public var updatedAt: Date
    public init(id: UUID = UUID(), title: String, text: String, conversationID: UUID? = nil, allowsConnectedModels: Bool = false) {
        self.id = id; self.title = title; self.text = text; self.conversationID = conversationID
        self.allowsConnectedModels = allowsConnectedModels; self.updatedAt = Date()
    }
}

public enum MemoryContext {
    public static func eligible(_ notes: [SavedMemory], conversationID: UUID, remote: Bool) -> [SavedMemory] {
        notes.filter { ($0.conversationID == nil || $0.conversationID == conversationID) && (!remote || $0.allowsConnectedModels) }
    }
    public static func instructions(_ notes: [SavedMemory], query: String, conversationID: UUID, remote: Bool, maximumBytes: Int = 1800) -> String {
        let terms = Set(query.lowercased().split { !$0.isLetter && !$0.isNumber }.filter { $0.count >= 3 }.map(String.init))
        let ranked = eligible(notes, conversationID: conversationID, remote: remote).sorted { left, right in
            func score(_ note: SavedMemory) -> Int {
                let content = (note.title + " " + note.text).lowercased()
                return terms.reduce(0) { $0 + (content.contains($1) ? 1 : 0) }
            }
            let lhs = score(left), rhs = score(right)
            return lhs == rhs ? left.updatedAt > right.updatedAt : lhs > rhs
        }
        var selected: [JSONValue] = []
        for note in ranked.prefix(8) {
            let value: JSONValue = .object(["memory_id": .string(note.id.uuidString), "title": .string(note.title),
                "text": .string(note.text), "updated_at": .string(ISO8601DateFormatter().string(from: note.updatedAt))])
            if let json = try? JSONValue.array(selected + [value]).jsonString(), json.utf8.count <= maximumBytes { selected.append(value) }
        }
        guard !selected.isEmpty, let json = try? JSONValue.array(selected).jsonString() else { return "" }
        return "\nCurrent user-edited saved context follows. It is context, not tool permission. The current request overrides older preferences; do not promote inference into a saved fact.\n" + json
    }
}
