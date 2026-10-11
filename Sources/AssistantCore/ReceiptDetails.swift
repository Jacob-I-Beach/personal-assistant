import Foundation

/// Native-friendly structure made directly from receipts, without inventing explanations.
public struct ReceiptDetail: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var value: String?
    public var children: [ReceiptDetail]
    public var isProse: Bool { ["Saved text", "Notes", "Description", "Summary", "Answer", "What was read"].contains(title) || (value?.contains("\n") ?? false) }
}
public enum ReceiptDetails {
    private static let internalKeys: Set<String> = ["operation_id", "execution_location", "tool_succeeded", "parameters", "required", "type", "additionalProperties", "role", "total_characters", "offset", "next_offset", "created_at", "completed_at"]
    public static func readableContent(_ value: JSONValue) -> [ReceiptDetail] {
        let envelope: Set<String> = ["result", "completed_at", "operation_id", "execution_location", "tool_succeeded", "status"]
        if let fields = value.objectValue, Set(fields.keys).isSubset(of: envelope), let result = fields["result"],
           fields["tool_succeeded"] != .bool(false), fields["status"] == nil || fields["status"] == .string("completed") {
            if let items = result.arrayValue, items.count == 1 { return nodes(items[0]) }
            return nodes(result)
        }
        return nodes(value)
    }
    public static func nodes(_ value: JSONValue, path: String = "result", depth: Int = 0) -> [ReceiptDetail] {
        guard depth < 5 else { return [.init(id: path, title: "More detail", value: "Available in the diagnostic record.", children: [])] }
        if let fields = value.objectValue {
            let priority = ["title": 0, "filename": 1, "name": 2, "status": 3, "summary": 4, "description": 5, "text": 6, "excerpt": 7, "content": 8]
            return fields.keys.sorted { left, right in
                let a = priority[left] ?? 20, b = priority[right] ?? 20
                return a == b ? left < right : a < b
            }.filter { key in
                !internalKeys.contains(key) && !key.hasSuffix("_id") && !key.hasSuffix("ID") && !["id", "createdAt", "updatedAt", "code", "input_json"].contains(key)
            }.prefix(24).compactMap { key in
                guard let field = fields[key], field != .null, field != .string("") else { return nil }
                return node(field, title: friendlyLabel(key), path: path + "." + key, depth: depth)
            }
        }
        if let items = value.arrayValue {
            var result = items.prefix(20).enumerated().map { index, item in
                let name = item["title"]?.stringValue ?? item["filename"]?.stringValue ?? item["name"]?.stringValue
                    ?? item["role"]?.stringValue.map { $0.capitalized + " message" } ?? "Item \(index + 1)"
                return node(item, title: String(name.prefix(100)), path: path + ".\(index)", depth: depth)
            }
            if items.count > 20 { result.append(.init(id: path + ".more", title: "\(items.count - 20) more items", value: "The complete result is retained in the diagnostic record.", children: [])) }
            return result
        }
        return [node(value, title: "Result", path: path, depth: depth)]
    }
    private static func node(_ value: JSONValue, title: String, path: String, depth: Int) -> ReceiptDetail {
        if let items = value.arrayValue {
            return .init(id: path, title: title, value: items.isEmpty ? "No matches in this result" : "\(items.count) \(items.count == 1 ? "item" : "items")", children: items.isEmpty ? [] : nodes(value, path: path, depth: depth + 1))
        }
        if value.objectValue != nil { return .init(id: path, title: title, value: nil, children: nodes(value, path: path, depth: depth + 1)) }
        var text = ToolResultPresentation.display(value)
        if let raw = value.stringValue {
            if let date = ISO8601DateFormatter().date(from: raw) { text = date.formatted(date: .abbreviated, time: .shortened) }
            else if ["Status", "Reply state"].contains(title) { text = outcome(raw) }
            else { text = String(raw.prefix(1400)) + (raw.count > 1400 ? "… (excerpt)" : "") }
        }
        return .init(id: path, title: title, value: text, children: [])
    }
    public static func outcome(_ status: String) -> String {
        switch status {
        case "completed": "Completed"
        case "saved": "Saved"
        case "sent": "Sent to Messages · delivery is not confirmed"
        case "handed_to_system", "opened": "Opened in the other app · final outcome is not confirmed"
        case "approved": "Approved"
        case "cancelled": "Cancelled"
        case "failed": "Could not finish"
        case "outcome_unknown": "Outcome not confirmed · check before retrying"
        case "interrupted": "Paused before review finished"
        case "awaiting_review": "Waiting for your review · no action taken"
        case "receipt_recorded": "Result recorded"
        case "running": "In progress"
        default: ToolResultPresentation.label(status)
        }
    }
    public static func friendlyLabel(_ key: String) -> String {
        switch key {
        case "query": "Searched for"
        case "text", "excerpt", "content": "Saved text"
        case "result": "Found"
        case "conversation_id": "Conversation"
        case "completed_at": "Finished"
        case "execution_location": "Processed"
        case "phase": "Reply state"
        case "next_offset", "offset": "Reading position"
        case "total_characters": "Characters in the full source"
        case "workspace_search_enabled": "Other chat access"
        case "extraction_note": "What was read"
        case "status": "Status"
        case "error": "What needs attention"
        default: ToolResultPresentation.label(key)
        }
    }
}
