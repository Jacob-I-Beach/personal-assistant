import Foundation

/// The app owns durable history independently of provider sessions. Credentials are never stored here.
public actor LocalStore {
    public nonisolated let root: URL
    private let files = FileManager.default

    public init(root: URL) throws {
        self.root = root
        for directory in [root, root.appendingPathComponent("conversations"), root.appendingPathComponent("captures")] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
    public func save(_ conversation: Conversation) throws {
        guard conversation.schemaVersion == 1 else { throw AssistantError.unsupportedSchema(conversation.schemaVersion) }
        var updated = conversation
        updated.updatedAt = Date()
        try write(updated, to: conversationURL(conversation.id))
    }
    public func loadConversation(_ id: UUID) throws -> Conversation {
        var c: Conversation = try read(conversationURL(id))
        guard c.schemaVersion == 1 else { throw AssistantError.unsupportedSchema(c.schemaVersion) }
        c.recoverInterruptedMessages()
        return c
    }
    public func conversations() throws -> [Conversation] {
        let directory = root.appendingPathComponent("conversations")
        return try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { url in
                var value: Conversation = try read(url)
                guard value.schemaVersion == 1 else { throw AssistantError.unsupportedSchema(value.schemaVersion) }
                value.recoverInterruptedMessages()
                return value
            }.sorted { $0.updatedAt > $1.updatedAt }
    }
    public func saveCapture(_ observation: CaptureObservation, jpeg: Data) throws {
        try observation.validate()
        guard !jpeg.isEmpty, jpeg.count <= 30 * 1024 * 1024 else {
            throw AssistantError.invalidCapture("The capture image is empty or exceeds the capture size limit.")
        }
        let directory = captureDirectory(observation.id)
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        try jpeg.write(to: directory.appendingPathComponent("image.jpg"), options: .atomic)
        // The manifest is the commit record: no manifest is visible until the image write succeeded.
        try write(observation, to: directory.appendingPathComponent("observation.json"))
    }
    public func loadCapture(_ id: UUID) throws -> CaptureObservation {
        let observation: CaptureObservation = try read(captureDirectory(id).appendingPathComponent("observation.json"))
        guard observation.id == id else { throw AssistantError.invalidCapture("Capture identity mismatch.") }
        try observation.validate()
        return observation
    }
    public func captures() throws -> [CaptureObservation] {
        try files.contentsOfDirectory(at: root.appendingPathComponent("captures"), includingPropertiesForKeys: nil)
            .compactMap { UUID(uuidString: $0.lastPathComponent) }
            .filter { files.fileExists(atPath: captureDirectory($0).appendingPathComponent("observation.json").path) }
            .map { try loadCapture($0) }.sorted { $0.capturedAt > $1.capturedAt }
    }
    public func imageData(_ id: UUID) throws -> Data {
        _ = try loadCapture(id)
        return try Data(contentsOf: captureDirectory(id).appendingPathComponent("image.jpg"))
    }
    public func captureManifestURL(_ id: UUID) throws -> URL {
        _ = try loadCapture(id)
        return captureDirectory(id).appendingPathComponent("observation.json")
    }
    public func captureImageURL(_ id: UUID) throws -> URL {
        _ = try loadCapture(id)
        return captureDirectory(id).appendingPathComponent("image.jpg")
    }
    private func captureDirectory(_ id: UUID) -> URL { root.appendingPathComponent("captures").appendingPathComponent(id.uuidString) }
    private func conversationURL(_ id: UUID) -> URL { root.appendingPathComponent("conversations").appendingPathComponent(id.uuidString + ".json") }
    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: url, options: .atomic)
    }
    private func read<T: Decodable>(_ url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        guard data.count <= 40 * 1024 * 1024 else { throw AssistantError.invalidCapture("Saved record is unexpectedly large.") }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }
}
