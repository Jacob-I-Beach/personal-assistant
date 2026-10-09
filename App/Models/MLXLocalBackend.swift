import AssistantCore
import CoreImage
import Foundation
import HuggingFace
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import MLXVLM
import Tokenizers

/// The model is downloaded only by an explicit user action. Chat loads exclusively from the saved directory.
actor MLXLocalBackend: ModelBackend {
    nonisolated let id: String
    nonisolated let networkDestination: String? = nil
    private let repository: String
    private let revision: String
    private let root: URL
    private let responseTokens: Int
    private var container: ModelContainer?
    private var busy = false

    init(repository: String, revision: String, root: URL, responseTokens: Int) {
        self.repository = repository; self.revision = revision; self.root = root
        self.responseTokens = responseTokens; self.id = "mlx:\(repository)@\(revision)"
    }

    private struct DownloadRecord: Codable {
        var repository: String
        var revision: String
        var relativeDirectory: String
    }
    private var recordURL: URL { root.appendingPathComponent("selected-model.json") }

    func download(allowCellular: Bool, progress: @Sendable @escaping (Double) -> Void) async throws {
        guard !busy else { throw AssistantError.busy }
        busy = true; defer { busy = false }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.allowsCellularAccess = allowCellular
        let hub = HubClient(session: URLSession(configuration: configuration), host: URL(string: "https://huggingface.co")!,
                            bearerToken: nil, cache: HubCache(cacheDirectory: root.appendingPathComponent("hub")))
        let downloader = #hubDownloader(hub)
        let directory = try await downloader.download(
            id: repository, revision: revision,
            matching: ["*.json", "*.safetensors", "*.txt", "*.model", "*.jinja", "LICENSE*", "README.md"],
            useLatest: false, progressHandler: { progress($0.fractionCompleted) })
        let base = root.standardizedFileURL.path + "/"
        guard directory.standardizedFileURL.path.hasPrefix(base) else {
            throw AssistantError.provider("The model downloader returned a location outside the model store.")
        }
        let record = DownloadRecord(repository: repository, revision: revision,
                                    relativeDirectory: String(directory.standardizedFileURL.path.dropFirst(base.count)))
        try JSONEncoder().encode(record).write(to: recordURL, options: .atomic)
        container = nil
        try await loadFromDisk()
        progress(1)
    }

    func unload() throws {
        guard !busy else { throw AssistantError.busy }
        container = nil
        MLX.Memory.clearCache()
    }

    private func loadFromDisk() async throws {
        if container != nil { return }
        guard FileManager.default.fileExists(atPath: recordURL.path) else {
            throw AssistantError.provider("Download the selected model in Settings before using local chat.")
        }
        let record = try JSONDecoder().decode(DownloadRecord.self, from: Data(contentsOf: recordURL))
        guard record.repository == repository, record.revision == revision else {
            throw AssistantError.provider("The selected model has not been downloaded. Open Settings to download it.")
        }
        let directory = root.appendingPathComponent(record.relativeDirectory).standardizedFileURL
        guard directory.path.hasPrefix(root.standardizedFileURL.path + "/") else {
            throw AssistantError.provider("Invalid saved model location.")
        }
        MLX.Memory.cacheLimit = 32 * 1024 * 1024
        // This first native provider uses the VLM factory: the selected Qwen checkpoint supports images and text.
        container = try await VLMModelFactory.shared.loadContainer(from: directory, using: #huggingFaceTokenizerLoader())
    }

    nonisolated func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do { try await self.generate(request, output: continuation); continuation.finish() }
                catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private func generate(_ request: ModelRequest, output: AsyncThrowingStream<ModelEvent, any Error>.Continuation) async throws {
        guard !busy else { throw AssistantError.busy }
        busy = true; defer { busy = false }
        try await loadFromDisk()
        guard let container else { throw AssistantError.provider("The local model did not load.") }
        var messages: [Chat.Message] = [.system(request.instructions)]
        for entry in request.messages {
            let m = entry.message
            let images: [UserInput.Image] = try entry.images.map { image in
                guard let value = CIImage(data: image.jpeg) else { throw AssistantError.invalidCapture("The attached image cannot be decoded.") }
                return .ciImage(value, label: image.captureID.uuidString)
            }
            switch m.role {
            case .user: messages.append(.user(m.text, images: images))
            case .assistant:
                let calls = try m.toolCalls.map { call in
                    let arguments = try JSONDecoder().decode([String: MLXLMCommon.JSONValue].self, from: JSONEncoder().encode(call.arguments))
                    return MLXLMCommon.ToolCall(function: .init(name: call.name, arguments: arguments), id: call.id)
                }
                messages.append(.assistant(m.text, toolCalls: calls.isEmpty ? nil : calls))
            case .tool: messages.append(.tool(m.text, id: m.toolCallID))
            }
        }
        let specs: [ToolSpec] = request.tools.map { tool in
            ["type": "function", "function": ["name": tool.name, "description": tool.description,
                                               "parameters": tool.parameters.sendableValue] as [String: any Sendable]]
        }
        let session = ChatSession(container, generateParameters: .init(maxTokens: responseTokens, temperature: 0.4),
                                  additionalContext: ["enable_thinking": false], tools: specs.isEmpty ? nil : specs)
        var calls: [AssistantCore.ToolCall] = []
        var stoppedNormally = false
        for try await event in session.streamDetails(to: messages) {
            try Task.checkCancellation()
            switch event {
            case .chunk(let text): output.yield(.textDelta(text))
            case .toolCall(let call):
                let arguments = try JSONDecoder().decode(AssistantCore.JSONValue.self, from: JSONEncoder().encode(call.function.arguments))
                calls.append(AssistantCore.ToolCall(id: call.id ?? UUID().uuidString, name: call.function.name, arguments: arguments))
            case .rejectedToolCall:
                throw AssistantError.invalidTool("The local model produced an invalid tool request. No tool was executed.")
            case .info(let info):
                switch info.stopReason {
                case .stop: stoppedNormally = true
                case .cancelled: throw CancellationError()
                case .length: throw AssistantError.incompleteResponse
                }
            }
        }
        try Task.checkCancellation()
        guard stoppedNormally else { throw AssistantError.incompleteResponse }
        for call in calls { output.yield(.toolCall(call)) }
        output.yield(.completed)
    }
}

private extension AssistantCore.JSONValue {
    var sendableValue: any Sendable {
        switch self {
        case .object(let value): value.mapValues(\.sendableValue)
        case .array(let value): value.map(\.sendableValue)
        case .string(let value): value
        case .number(let value): value
        case .bool(let value): value
        case .null: Optional<String>.none
        }
    }
}
