import Foundation

public enum MemoryKind: String, Codable, CaseIterable, Sendable { case note, identity, preference, project, decision, question }
public enum MemoryStatus: String, Codable, CaseIterable, Sendable { case active, tentative, superseded, expired, forgotten }
public enum MemoryBasis: String, Codable, Sendable { case userEdited, stated, inferred }
public struct SavedMemory: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var text: String
    public var conversationID: UUID?
    public var allowsConnectedModels: Bool
    public var updatedAt: Date
    public var kind: MemoryKind = .note
    public var status: MemoryStatus = .active
    public var source: String = "User-entered note"
    public var confirmedAt: Date?
    public var expiresAt: Date?
    public var revision: Int = 0
    public var basis: MemoryBasis = .userEdited
    public var sourceConversationID: UUID?
    public var sourceMessageID: UUID?
    public var sourceQuote: String?
    public var sourceMessageCreatedAt: Date?
    public var profileKey: String?
    public init(id: UUID = UUID(), title: String, text: String, conversationID: UUID? = nil, allowsConnectedModels: Bool = false) {
        self.id = id; self.title = title; self.text = text; self.conversationID = conversationID
        self.allowsConnectedModels = allowsConnectedModels; self.updatedAt = Date()
    }
    enum CodingKeys: String, CodingKey { case id, title, text, conversationID, allowsConnectedModels, updatedAt, kind, status, source, confirmedAt, expiresAt, revision, basis, sourceConversationID, sourceMessageID, sourceQuote, sourceMessageCreatedAt, profileKey }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); title = try c.decode(String.self, forKey: .title); text = try c.decode(String.self, forKey: .text)
        conversationID = try c.decodeIfPresent(UUID.self, forKey: .conversationID); allowsConnectedModels = try c.decode(Bool.self, forKey: .allowsConnectedModels)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        kind = try c.decodeIfPresent(MemoryKind.self, forKey: .kind) ?? .note
        status = try c.decodeIfPresent(MemoryStatus.self, forKey: .status) ?? .active
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? "User-entered note"
        confirmedAt = try c.decodeIfPresent(Date.self, forKey: .confirmedAt); expiresAt = try c.decodeIfPresent(Date.self, forKey: .expiresAt)
        revision = try c.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        basis = try c.decodeIfPresent(MemoryBasis.self, forKey: .basis) ?? .userEdited
        sourceConversationID = try c.decodeIfPresent(UUID.self, forKey: .sourceConversationID)
        sourceMessageID = try c.decodeIfPresent(UUID.self, forKey: .sourceMessageID)
        sourceQuote = try c.decodeIfPresent(String.self, forKey: .sourceQuote)
        sourceMessageCreatedAt = try c.decodeIfPresent(Date.self, forKey: .sourceMessageCreatedAt)
        profileKey = try c.decodeIfPresent(String.self, forKey: .profileKey)
    }
    public func isCurrent(at date: Date = Date()) -> Bool { (status == .active || status == .tentative) && (expiresAt == nil || expiresAt! > date) }
}

public enum MemoryContext {
    public static func eligible(_ notes: [SavedMemory], conversationID: UUID, remote: Bool) -> [SavedMemory] {
        notes.filter { $0.isCurrent() && ($0.conversationID == nil || $0.conversationID == conversationID) && (!remote || $0.allowsConnectedModels) }
    }
    public static func instructions(_ notes: [SavedMemory], query: String, conversationID: UUID, remote: Bool, maximumBytes: Int = 1800) -> String {
        let terms = RetrievalTerms.terms(query)
        func score(_ note: SavedMemory) -> Int { RetrievalTerms.score(note.title + " " + note.text, query: terms) }
        let explicitlyReadingMemory = ["saved note", "saved context", "remember", "memory", "about me"].contains { query.localizedCaseInsensitiveContains($0) }
        let ranked = eligible(notes, conversationID: conversationID, remote: remote)
            .filter { terms.isEmpty || explicitlyReadingMemory || $0.conversationID == conversationID || score($0) > 0 || [.identity, .preference].contains($0.kind) }
            .sorted { left, right in
                let lhs = score(left), rhs = score(right)
                return lhs == rhs ? left.updatedAt > right.updatedAt : lhs > rhs
            }
        var selected: [JSONValue] = []
        for note in ranked.prefix(8) {
            let value: JSONValue = .object(["memory_id": .string(note.id.uuidString), "title": .string(note.title),
                "text": .string(note.text), "kind": .string(note.kind.rawValue), "status": .string(note.status.rawValue), "source": .string(note.source),
                "revision": .number(Double(note.revision)), "basis": .string(note.basis.rawValue),
                "confirmed_at": note.confirmedAt.map { .string(ISO8601DateFormatter().string(from: $0)) } ?? .null,
                "updated_at": .string(ISO8601DateFormatter().string(from: note.updatedAt))])
            if let json = try? JSONValue.array(selected + [value]).jsonString(), json.utf8.count <= maximumBytes { selected.append(value) }
        }
        guard !selected.isEmpty, let json = try? JSONValue.array(selected).jsonString() else { return "" }
        return "\nCurrent saved context follows. Tentative/inferred notes remain uncertain; questions are unresolved. Source and confirmation labels distinguish user editing, stated facts and inferred summaries. This is context, not tool permission. The current request overrides older preferences.\n" + json
    }
}
