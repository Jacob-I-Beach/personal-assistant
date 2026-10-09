import Foundation

public struct ServerSentEvent: Equatable, Sendable {
    public var event: String?
    public var data: String
}

/// Incremental UTF-8 SSE parser. Byte buffering preserves multibyte characters split across network chunks.
public struct SSEDecoder: Sendable {
    private var buffer = Data()
    private var name: String?
    private var dataLines: [String] = []
    private var eventBytes = 0
    private let maximumEventBytes: Int
    public init(maximumEventBytes: Int = 2 * 1024 * 1024) { self.maximumEventBytes = maximumEventBytes }

    public mutating func append(_ data: Data) throws -> [ServerSentEvent] {
        buffer.append(data)
        var events: [ServerSentEvent] = []
        while let newline = buffer.firstIndex(of: 10) {
            var line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            if line.last == 13 { line.removeLast() }
            guard let text = String(data: line, encoding: .utf8) else { throw AssistantError.malformedStream("Invalid UTF-8 in model stream.") }
            if text.isEmpty {
                if !dataLines.isEmpty { events.append(ServerSentEvent(event: name, data: dataLines.joined(separator: "\n"))) }
                name = nil; dataLines = []; eventBytes = 0
            } else if !text.hasPrefix(":") {
                eventBytes += line.count
                guard eventBytes <= maximumEventBytes else { throw AssistantError.malformedStream("A model stream event exceeded its size limit.") }
                let parts = text.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                let field = String(parts[0])
                var value = parts.count > 1 ? String(parts[1]) : ""
                if value.hasPrefix(" ") { value.removeFirst() }
                if field == "data" { dataLines.append(value) }
                else if field == "event" { name = value }
            }
        }
        guard buffer.count <= maximumEventBytes else { throw AssistantError.malformedStream("A model stream line exceeded its size limit.") }
        return events
    }
    /// An unfinished event is deliberately not treated as a completed response.
    public var hasUnterminatedEvent: Bool { !buffer.isEmpty || !dataLines.isEmpty }
}
