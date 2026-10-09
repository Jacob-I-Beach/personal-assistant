import Foundation

public struct WatchRequest: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var text: String
    public var createdAt: Date
    public var conversationID: UUID?
    public var schemaVersion = 1
    public init(id: UUID = UUID(), text: String, conversationID: UUID? = nil, createdAt: Date = Date()) {
        self.id = id; self.text = text; self.conversationID = conversationID; self.createdAt = createdAt
    }
    public func isValid(at now: Date = Date()) -> Bool {
        schemaVersion == 1 && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.utf8.count <= 8000
            && now.timeIntervalSince(createdAt) >= -300 && now.timeIntervalSince(createdAt) < 86_400
    }
}
public struct WatchReply: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable { case queued, needsPhone, working, complete, failed }
    public var requestID: UUID
    public var conversationID: UUID?
    public var state: State
    public var message: String
    public var modelName: String
    public init(requestID: UUID, conversationID: UUID?, state: State, message: String, modelName: String) {
        self.requestID = requestID; self.conversationID = conversationID; self.state = state; self.message = message; self.modelName = modelName
    }
}
public enum WatchWire {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
    public static func decode<T: Decodable>(_ type: T.Type, data: Data) throws -> T {
        guard data.count <= 16_384 else { throw CocoaError(.coderInvalidValue) }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
}
