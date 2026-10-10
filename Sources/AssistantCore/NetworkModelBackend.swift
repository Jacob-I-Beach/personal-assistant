import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum NetworkProtocol: String, Codable, Sendable { case responses, chatCompletions }

public struct NetworkModelBackend: ModelBackend {
    public let baseURL: URL
    public let model: String
    public let wireProtocol: NetworkProtocol
    private let credential: String
    private let transport: any HTTPStreamingTransport
    private let chatGPTAccountID: String?
    private let webSearchEnabled: Bool
    public var id: String { "\(wireProtocol.rawValue):\(baseURL.absoluteString):\(model)" + (chatGPTAccountID.map { ":account:\($0)" } ?? "") + (webSearchEnabled ? ":web-search" : "") }
    public var networkDestination: String? { chatGPTAccountID.map { "chatgpt-account:" + $0 } ?? baseURL.absoluteString }
    public var supportsFileInputs: Bool { wireProtocol == .responses && baseURL.absoluteString == "https://api.openai.com/v1" }
    public var contextLimits: ContextLimits {
        ContextLimits(maximumTextBytes: chatGPTAccountID == nil ? 32_768 : 128_000, maximumImages: 4)
    }

    public init(baseURL: URL, model: String, wireProtocol: NetworkProtocol,
                credential: String = "", transport: any HTTPStreamingTransport = URLSessionStreamingTransport(), chatGPTAccountID: String? = nil,
                webSearchEnabled: Bool = false) throws {
        try EndpointPolicy.validate(baseURL)
        guard !credential.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw AssistantError.invalidEndpoint("The credential contains a line break or control character. Paste only the credential value.")
        }
        if chatGPTAccountID != nil {
            guard baseURL.absoluteString == "https://api.openai.com/v1", wireProtocol == .responses else {
                throw AssistantError.invalidEndpoint("ChatGPT account credentials can only be used with the supported OpenAI Responses endpoint.")
            }
        }
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AssistantError.invalidEndpoint("Enter a model identifier in Settings.")
        }
        self.baseURL = baseURL; self.model = model; self.wireProtocol = wireProtocol
        self.credential = credential; self.transport = transport
        self.chatGPTAccountID = chatGPTAccountID
        guard !webSearchEnabled || chatGPTAccountID != nil else {
            throw AssistantError.invalidEndpoint("This web-search setting is available for ChatGPT account connections only.")
        }
        self.webSearchEnabled = webSearchEnabled
    }

    public func makeRequest(_ input: ModelRequest) throws -> URLRequest {
        let suffix = wireProtocol == .responses ? "responses" : "chat/completions"
        var request = URLRequest(url: baseURL.appendingPathComponent(suffix))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if !credential.isEmpty { request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization") }
        let body = wireProtocol == .responses ? try responsesBody(input) : try chatBody(input)
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    public func stream(_ input: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeRequest(input)
                    var sse = SSEDecoder()
                    var wire = ModelWireDecoder(wireProtocol: wireProtocol)
                    for try await data in transport.stream(request) {
                        try Task.checkCancellation()
                        for event in try sse.append(data) {
                            for result in try wire.consume(event) { continuation.yield(result) }
                        }
                    }
                    try Task.checkCancellation()
                    guard wire.completed else { throw AssistantError.incompleteResponse }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private func imagePart(_ image: ModelImage, responses: Bool) -> JSONValue {
        let url = "data:image/jpeg;base64," + image.jpeg.base64EncodedString()
        if responses { return .object(["type": .string("input_image"), "image_url": .string(url), "detail": .string("auto")]) }
        return .object(["type": .string("image_url"), "image_url": .object(["url": .string(url)])])
    }

    private func responsesBody(_ input: ModelRequest) throws -> JSONValue {
        var items: [JSONValue] = []
        for entry in input.messages {
            let m = entry.message
            if m.role == .tool {
                guard let callID = m.toolCallID else { continue }
                items.append(.object(["type": .string("function_call_output"), "call_id": .string(callID), "output": .string(m.text)]))
            } else if m.role == .assistant, let state = m.continuation, state.providerID == id, !state.items.isEmpty {
                // Retain provider-specific reasoning/output items only for the exact original model.
                items.append(contentsOf: state.items)
            } else {
                if !m.text.isEmpty || !entry.images.isEmpty || !entry.files.isEmpty {
                    let type = m.role == .user ? "input_text" : "output_text"
                    var content: [JSONValue] = [.object(["type": .string(type), "text": .string(m.text)])]
                    if m.role == .user { content += entry.images.map { imagePart($0, responses: true) } }
                    if m.role == .user && supportsFileInputs {
                        content += entry.files.map { .object(["type": .string("input_file"), "filename": .string($0.filename),
                            "file_data": .string("data:\($0.mediaType);base64," + $0.data.base64EncodedString())]) }
                    }
                    items.append(.object(["role": .string(m.role.rawValue), "content": .array(content)]))
                }
                for call in m.toolCalls {
                    var item: [String: JSONValue] = ["type": .string("function_call"), "call_id": .string(call.id),
                        "name": .string(call.name), "arguments": .string(try call.arguments.jsonString())]
                    if chatGPTAccountID != nil { item["namespace"] = .string("assistant") }
                    items.append(.object(item))
                }
            }
        }
        var body: [String: JSONValue] = [
            "model": .string(model), "stream": .bool(true), "store": .bool(false),
            "instructions": .string(input.instructions + (webSearchEnabled ? "\nWeb search is enabled subject to the selected model and account policy. Use it for current or sourced facts. Cite returned sources with visible Markdown links; do not invent citations." : "")), "input": .array(items),
            "include": .array([.string("reasoning.encrypted_content")]),
        ]
        if !input.tools.isEmpty {
            let functions = input.tools.map { tool in
                .object(["type": .string("function"), "name": .string(tool.name),
                         "description": .string(tool.description), "parameters": tool.parameters, "strict": .bool(true)])
            } as [JSONValue]
            body["tools"] = chatGPTAccountID == nil ? .array(functions) : .array([
                .object(["type": .string("namespace"), "name": .string("assistant"),
                         "description": .string("Tools executed by the user's assistant app."), "tools": .array(functions)])
            ])
        }
        if webSearchEnabled {
            body["tools"] = .array((body["tools"]?.arrayValue ?? []) + [.object(["type": .string("web_search")])])
        }
        return .object(body)
    }

    private func chatBody(_ input: ModelRequest) throws -> JSONValue {
        var messages: [JSONValue] = [.object(["role": .string("system"), "content": .string(input.instructions)])]
        for entry in input.messages {
            let m = entry.message
            var item: [String: JSONValue] = ["role": .string(m.role.rawValue)]
            if entry.images.isEmpty { item["content"] = .string(m.text) }
            else {
                item["content"] = .array([.object(["type": .string("text"), "text": .string(m.text)])]
                    + entry.images.map { imagePart($0, responses: false) })
            }
            if let callID = m.toolCallID { item["tool_call_id"] = .string(callID) }
            if !m.toolCalls.isEmpty {
                item["tool_calls"] = .array(try m.toolCalls.map { call in
                    .object(["id": .string(call.id), "type": .string("function"),
                             "function": .object(["name": .string(call.name), "arguments": .string(try call.arguments.jsonString())])])
                })
            }
            messages.append(.object(item))
        }
        var body: [String: JSONValue] = ["model": .string(model), "stream": .bool(true), "messages": .array(messages)]
        if !input.tools.isEmpty {
            body["tools"] = .array(input.tools.map { tool in
                .object(["type": .string("function"), "function": .object([
                    "name": .string(tool.name), "description": .string(tool.description), "parameters": tool.parameters,
                ])])
            })
        }
        return .object(body)
    }
}

/// Tool calls become executable only after the provider's explicit terminal completion marker.
public struct ModelWireDecoder: Sendable {
    public private(set) var completed = false
    private let wireProtocol: NetworkProtocol
    private struct PartialCall: Sendable { var id = ""; var name = ""; var arguments = "" }
    private var chatCalls: [Int: PartialCall] = [:]
    private var responseItems: [Int: JSONValue] = [:]
    private var streamedText = ""
    private var finishedTextParts: [Int: [Int: String]] = [:]
    private var finishReason: String?
    public init(wireProtocol: NetworkProtocol) { self.wireProtocol = wireProtocol }

    public mutating func consume(_ event: ServerSentEvent) throws -> [ModelEvent] {
        guard !completed else { return [] }
        if wireProtocol == .chatCompletions && event.data == "[DONE]" {
            guard let finishReason, ["stop", "tool_calls"].contains(finishReason) else { throw AssistantError.incompleteResponse }
            let calls = try chatCalls.sorted { $0.key < $1.key }.map { _, value -> ModelEvent in
                guard !value.id.isEmpty, !value.name.isEmpty else { throw AssistantError.malformedStream("Incomplete tool call.") }
                return .toolCall(ToolCall(id: value.id, name: value.name, arguments: try JSONValue.parse(value.arguments)))
            }
            completed = true
            return calls + [.completed]
        }
        let payload = try JSONValue.parse(event.data)
        if let error = payload["error"], error != .null { throw AssistantError.provider(error["message"]?.stringValue ?? "Model server reported an error.") }
        return try wireProtocol == .responses ? consumeResponses(payload) : consumeChat(payload)
    }

    private mutating func consumeChat(_ payload: JSONValue) throws -> [ModelEvent] {
        guard let choice = payload["choices"]?.arrayValue?.first else { return [] }
        if let reason = choice["finish_reason"]?.stringValue { finishReason = reason }
        var results: [ModelEvent] = []
        let delta = choice["delta"]
        if let text = delta?["content"]?.stringValue { results.append(.textDelta(text)) }
        for item in delta?["tool_calls"]?.arrayValue ?? [] {
            guard let value = item["index"]?.numberValue, value >= 0, value < 32, value.rounded() == value else {
                throw AssistantError.malformedStream("Invalid tool-call stream index.")
            }
            let index = Int(value)
            var call = chatCalls[index] ?? PartialCall()
            if let id = item["id"]?.stringValue { call.id = id }
            if let name = item["function"]?["name"]?.stringValue { call.name += name }
            if let arguments = item["function"]?["arguments"]?.stringValue { call.arguments += arguments }
            guard call.arguments.utf8.count <= 32768 else { throw AssistantError.malformedStream("Tool arguments are too large.") }
            chatCalls[index] = call
        }
        return results
    }

    private mutating func consumeResponses(_ payload: JSONValue) throws -> [ModelEvent] {
        switch payload["type"]?.stringValue {
        case "response.web_search_call.in_progress", "response.web_search_call.searching":
            return [.activity("Searching the web")]
        case "response.web_search_call.completed":
            return [.activity("Preparing the sourced response")]
        case "response.output_item.added":
            if payload["item"]?["type"]?.stringValue == "reasoning" { return [.activity("Thinking through the request")] }
            return []
        case "response.output_text.delta", "response.refusal.delta":
            guard let delta = payload["delta"]?.stringValue else { return [] }
            streamedText += delta
            return [.textDelta(delta)]
        case "response.output_text.done", "response.refusal.done":
            if let text = payload["text"]?.stringValue ?? payload["refusal"]?.stringValue {
                let output = try responseIndex(payload["output_index"]), content = try responseIndex(payload["content_index"])
                finishedTextParts[output, default: [:]][content] = text
            }
            return []
        case "response.output_item.done":
            if let index = payload["output_index"]?.numberValue, index >= 0, index < 128,
               index.rounded() == index, let item = payload["item"] { responseItems[Int(index)] = item }
            return []
        case "response.completed":
            if let status = payload["response"]?["status"]?.stringValue, status != "completed" { throw AssistantError.incompleteResponse }
            if let error = payload["response"]?["error"], error != .null {
                throw AssistantError.provider(error["message"]?.stringValue ?? "The model request failed.")
            }
            let terminalOutput = payload["response"]?["output"]?.arrayValue ?? []
            let output = terminalOutput.isEmpty ? responseItems.sorted { $0.key < $1.key }.map(\.value) : terminalOutput
            var events: [ModelEvent] = []
            for item in output where item["type"]?.stringValue == "function_call" {
                if let status = item["status"]?.stringValue, status != "completed" { throw AssistantError.incompleteResponse }
                guard let id = item["call_id"]?.stringValue, !id.isEmpty, let name = item["name"]?.stringValue, !name.isEmpty,
                      let arguments = item["arguments"]?.stringValue, arguments.utf8.count <= 32768 else {
                    throw AssistantError.malformedStream("Incomplete function call in completed response.")
                }
                events.append(.toolCall(ToolCall(id: id, name: name, arguments: try JSONValue.parse(arguments))))
            }
            var finalText = output.filter { $0["type"]?.stringValue == "message" }.flatMap { $0["content"]?.arrayValue ?? [] }
                .compactMap { part -> String? in
                    switch part["type"]?.stringValue {
                    case "output_text": part["text"]?.stringValue
                    case "refusal": part["refusal"]?.stringValue
                    default: nil
                    }
                }.joined()
            if finalText.isEmpty {
                finalText = finishedTextParts.sorted { $0.key < $1.key }.flatMap { $0.value.sorted { $0.key < $1.key }.map(\.value) }.joined()
            }
            if !finalText.isEmpty {
                guard finalText.utf8.starts(with: streamedText.utf8) else { throw AssistantError.malformedStream("The completed response changed text already received.") }
                let missing = String(decoding: finalText.utf8.dropFirst(streamedText.utf8.count), as: UTF8.self)
                if !missing.isEmpty { events.insert(.textDelta(missing), at: 0); streamedText += missing }
            }
            guard !streamedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !events.isEmpty else {
                throw AssistantError.provider("The model completed without an answer or a tool request. Your message and any attached images are saved. Try a new request or another model.")
            }
            var seen = Set<String>(), citations: [WebCitation] = []
            var annotationOffset = 0
            for part in output.filter({ $0["type"]?.stringValue == "message" }).flatMap({ $0["content"]?.arrayValue ?? [] }) {
                let partText = part["text"]?.stringValue ?? ""
                func position(_ key: String, in annotation: JSONValue) -> Int? {
                    guard let n = annotation[key]?.numberValue, n >= 0, n <= Double(partText.unicodeScalars.count), n.rounded() == n else { return nil }
                    return annotationOffset + Int(n)
                }
                for annotation in part["annotations"]?.arrayValue ?? [] where annotation["type"]?.stringValue == "url_citation" {
                    if let url = annotation["url"]?.stringValue,
                       let citation = WebCitation(title: annotation["title"]?.stringValue ?? "", url: url,
                                                  startIndex: position("start_index", in: annotation), endIndex: position("end_index", in: annotation)),
                       seen.insert(citation.id).inserted, citations.count < 32 { citations.append(citation) }
                }
                annotationOffset += partText.unicodeScalars.count
            }
            if !citations.isEmpty { events.append(.citations(citations)) }
            completed = true
            return events + [.continuation(output), .completed]
        case "response.failed", "error":
            throw AssistantError.provider(payload["response"]?["error"]?["message"]?.stringValue ?? payload["message"]?.stringValue ?? "The model request failed.")
        case "response.incomplete": throw AssistantError.incompleteResponse
        default: return []
        }
    }
    private func responseIndex(_ value: JSONValue?) throws -> Int {
        guard let value else { return 0 }
        guard let number = value.numberValue, number >= 0, number < 128, number.rounded() == number else {
            throw AssistantError.malformedStream("Invalid response content index.")
        }
        return Int(number)
    }
}
