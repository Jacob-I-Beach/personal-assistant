import Foundation

/// Only public messages and reported hosted actions belong in the visible transcript.
/// Opaque reasoning and executable function arguments remain in the provider continuation.
public struct ResponsePart: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case text, web }
    public var id: String
    public var kind: Kind
    public var text: String
    public var phase: String?
    public var citations: [WebCitation]
    public var web: WebActivity?

    public init(id: String, text: String, phase: String? = nil, citations: [WebCitation] = []) {
        self.id = id; kind = .text; self.text = text; self.phase = phase
        self.citations = citations; web = nil
    }
    public init(id: String, web: WebActivity) {
        self.id = id; kind = .web; text = ""; phase = nil; citations = []; self.web = web
    }
}

public struct WebActivity: Codable, Equatable, Sendable {
    public var status: String
    public var action: String
    public var queries: [String]
    public var sources: [WebCitation]
    public var pattern: String?
    public var isRunning: Bool { ["in_progress", "searching"].contains(status) }
    public var isSuccessful: Bool { status == "completed" }
    public var title: String {
        let verb = action == "open_page" ? "Reading a web page" : action == "find_in_page" ? "Finding text on a page" : "Searching the web"
        if isRunning { return verb }
        if !isSuccessful { return "Web activity incomplete" }
        return action == "open_page" ? "Read a web page" : action == "find_in_page" ? "Searched within a page" : "Searched the web"
    }
    public init(status: String, action: String = "search", queries: [String] = [], sources: [WebCitation] = [], pattern: String? = nil) {
        self.status = status; self.action = action; self.queries = queries; self.sources = sources; self.pattern = pattern
    }
}

public enum ResponsePresentation {
    public static func parts(from items: [JSONValue]) -> [ResponsePart] {
        parts(from: Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.offset, $0.element) }))
    }
    static func parts(from items: [Int: JSONValue]) -> [ResponsePart] {
        var result: [ResponsePart] = []
        for (index, item) in items.sorted(by: { $0.key < $1.key }) {
            // Include the index even when a malformed provider repeats an ID.
            let id = "\(index):" + (item["id"]?.stringValue ?? "output")
            switch item["type"]?.stringValue {
            case "message":
                guard item["role"]?.stringValue == nil || item["role"]?.stringValue == "assistant" else { continue }
                for (contentIndex, content) in (item["content"]?.arrayValue ?? []).enumerated() {
                    let type = content["type"]?.stringValue
                    guard type == "output_text" || type == "refusal",
                          let text = content[type == "refusal" ? "refusal" : "text"]?.stringValue, !text.isEmpty else { continue }
                    var seen = Set<String>()
                    let citations = (content["annotations"]?.arrayValue ?? []).compactMap { annotation -> WebCitation? in
                        guard annotation["type"]?.stringValue == "url_citation", let url = annotation["url"]?.stringValue else { return nil }
                        func position(_ key: String) -> Int? {
                            guard let n = annotation[key]?.numberValue, n >= 0, n <= Double(text.unicodeScalars.count), n.rounded() == n else { return nil }
                            return Int(n)
                        }
                        guard let citation = WebCitation(title: annotation["title"]?.stringValue ?? "", url: url,
                                                        startIndex: position("start_index"), endIndex: position("end_index")),
                              seen.insert(citation.id).inserted, seen.count <= 32 else { return nil }
                        return citation
                    }
                    result.append(ResponsePart(id: "\(id):\(contentIndex)", text: text, phase: item["phase"]?.stringValue, citations: citations))
                }
            case "web_search_call":
                let action = item["action"]
                var queries = action?["queries"]?.arrayValue?.compactMap(\.stringValue) ?? []
                if let query = action?["query"]?.stringValue, !queries.contains(query) { queries.insert(query, at: 0) }
                var seen = Set<String>()
                var sources = (action?["sources"]?.arrayValue ?? []).compactMap { source -> WebCitation? in
                    guard let url = source["url"]?.stringValue,
                          let citation = WebCitation(title: source["title"]?.stringValue ?? "", url: url),
                          seen.insert(url).inserted, seen.count <= 32 else { return nil }
                    return citation
                }
                if let url = action?["url"]?.stringValue, let citation = WebCitation(title: "", url: url), seen.insert(url).inserted {
                    sources.insert(citation, at: 0)
                }
                result.append(ResponsePart(id: id, web: WebActivity(
                    status: item["status"]?.stringValue ?? "incomplete",
                    action: action?["type"]?.stringValue ?? "search",
                    queries: Array(queries.prefix(8)).map { String($0.prefix(500)) },
                    sources: sources, pattern: action?["pattern"]?.stringValue.map { String($0.prefix(300)) })))
            default: break
            }
        }
        return result
    }
    public static func text(in parts: [ResponsePart]) -> String {
        parts.filter { $0.kind == .text }.map(\.text).joined(separator: "\n\n")
    }
    static func settled(_ parts: [ResponsePart], state: MessageState) -> [ResponsePart] {
        guard state != .streaming else { return parts }
        return parts.map { part in
            var result = part
            if result.web?.isRunning == true { result.web?.status = state == .failed ? "failed" : "incomplete" }
            return result
        }
    }
}

public extension Message {
    /// Reconstruct pre-0.3.1 chats from their saved provider items when the text matches.
    /// This changes presentation only; the original transcript is never rewritten.
    var displayParts: [ResponsePart] {
        if !responseParts.isEmpty { return ResponsePresentation.settled(responseParts, state: state) }
        guard role == .assistant, let continuation else { return [] }
        let recovered = ResponsePresentation.parts(from: continuation.items)
        let raw = recovered.filter { $0.kind == .text }.map(\.text).joined()
        guard raw == text || ResponsePresentation.text(in: recovered) == text else { return [] }
        return ResponsePresentation.settled(recovered, state: state)
    }
    var displayText: String { displayParts.isEmpty ? text : ResponsePresentation.text(in: displayParts) }
    var answerText: String {
        let parts = displayParts.filter { $0.kind == .text }
        let final = parts.filter { $0.phase == "final_answer" }
        return final.isEmpty ? displayText : final.map(\.text).joined(separator: "\n\n")
    }
    var displayCitations: [WebCitation] { displayParts.isEmpty ? citations : displayParts.flatMap(\.citations) }
}

public extension Conversation {
    /// One action group per completed user turn, after its final answer. Older turns remain usable
    /// while a new one streams; a stopped/failed/tool-only turn never masquerades as a final answer.
    func responseActionMessageIDs(isRunning: Bool) -> Set<UUID> {
        var result = Set<UUID>()
        var turn: [Message] = []
        func finish(_ messages: [Message], current: Bool) {
            guard !(current && isRunning),
                  let last = messages.last, last.role == .assistant, last.state == .complete,
                  last.toolCalls.isEmpty, !last.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let textParts = last.displayParts.filter { $0.kind == .text }
            guard textParts.isEmpty || textParts.contains(where: { $0.phase != "commentary" }) else { return }
            result.insert(last.id)
        }
        for message in messages {
            if message.role == .user { finish(turn, current: false); turn = [] }
            else { turn.append(message) }
        }
        finish(turn, current: true)
        return result
    }
}
