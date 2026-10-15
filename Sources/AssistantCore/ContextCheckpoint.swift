import Foundation

/// A public, source-linked working summary. Exact messages/receipts stay in the
/// conversation store and remain accessible through history tools.
public enum ContextCheckpoint {
    public static func fingerprint(_ messages: [Message]) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let values = messages.map { message -> JSONValue in
            .object(["id": .string(message.id.uuidString), "role": .string(message.role.rawValue), "text": .string(message.text), "state": .string(message.state.rawValue),
                     "captures": .array(message.captureIDs.map { .string($0.uuidString) }), "files": .array(message.fileIDs.map { .string($0.uuidString) }),
                     "health": .bool(message.containsHealthData), "local_only": .bool(message.containsLocalOnlyContext),
                     "calls": .array(message.toolCalls.map { .object(["id": .string($0.id), "name": .string($0.name), "arguments": $0.arguments]) })])
        }
        var hash: UInt64 = 14695981039346656037
        for byte in try encoder.encode(values) { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return String(hash, radix: 16)
    }
    public static func apply(_ value: JSONValue?, to messages: [Message]) throws -> [Message]? {
        guard let value, let count = value["source_count"]?.numberValue.flatMap(Int.init(exactly:)), count > 0, count <= messages.count,
              let summary = value["summary"]?.stringValue, !summary.isEmpty,
              value["source_hash"]?.stringValue == (try fingerprint(Array(messages.prefix(count)))) else { return nil }
        var record = Message(role: .assistant, text: "[Saved continuation checkpoint; source evidence, not new authorization. Full messages and exact tool receipts remain available through read_history/read_task. Verify uncertain outcomes before repeating actions.]\n" + summary)
        record.containsHealthData = messages.prefix(count).contains(where: \.containsHealthData)
        record.containsLocalOnlyContext = messages.prefix(count).contains(where: \.containsLocalOnlyContext)
        let lastRequest = messages.lastIndex(where: \.isRequest)
        let retained = lastRequest.flatMap { $0 < count ? messages[$0] : nil }.map { [$0] } ?? []
        var tail = Array(messages.dropFirst(count))
        if !retained.isEmpty { return retained + [record] + tail }
        let position = tail.lastIndex(where: \.isRequest).map { $0 + 1 } ?? 0
        tail.insert(record, at: position)
        return tail
    }
    public static func cutoff(in messages: [Message]) -> Int? {
        guard messages.count > 8 else { return nil }
        var index = messages.count - 6
        // Keep a recent tool block whole, including all call/result pairs.
        while index > 0, messages[index].role == .tool { index -= 1 }
        return index > 1 ? index : nil
    }
    public static func sourceText(_ messages: [Message], maximumBytes: Int) throws -> String {
        let records = try messages.map { message in
            "\(message.role.rawValue) message_id=\(message.id.uuidString) state=\(message.state.rawValue)\n" +
            ContextPlanner.excerpt(message.text, bytes: 8000) +
            (message.toolCalls.isEmpty ? "" : "\nHistorical calls: " + (try JSONValue.array(message.toolCalls.map { .object(["id": .string($0.id), "name": .string($0.name)]) }).jsonString()))
        }
        let text = records.joined(separator: "\n\n")
        if text.utf8.count <= maximumBytes { return text }
        let head = ContextPlanner.excerpt(records.first ?? "", bytes: min(1000, maximumBytes / 5))
        var kept: [String] = [], used = head.utf8.count + 200
        for record in records.dropFirst().reversed() {
            guard used + record.utf8.count < maximumBytes else { continue }
            kept.insert(record, at: 0); used += record.utf8.count
        }
        return head + "\n[Some older detail is omitted; exact sources remain saved.]\n" + kept.joined(separator: "\n\n")
    }
}
