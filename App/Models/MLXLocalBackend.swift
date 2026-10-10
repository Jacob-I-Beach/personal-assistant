import AssistantCore
import CoreImage
import CryptoKit
import Foundation
import HuggingFace
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import MLXVLM
import Tokenizers
import os

/// The model is downloaded only by an explicit user action. Chat loads exclusively from the saved directory.
actor MLXLocalBackend: ModelBackend {
    nonisolated let id: String
    nonisolated let networkDestination: String? = nil
    private let repository: String
    private let revision: String
    private let root: URL
    private let responseTokens: Int
    nonisolated let supportsVision: Bool
    private let weightBytes: Int64
    nonisolated var contextLimits: ContextLimits { ContextLimits(maximumTextBytes: 24_000, maximumImages: supportsVision ? 1 : 0) }
    private var container: ModelContainer?
    private var busy = false
    private var downloadBusy = false

    init(repository: String, revision: String, root: URL, responseTokens: Int, supportsVision: Bool = true, weightBytes: Int64 = 0) {
        self.repository = repository; self.revision = revision; self.root = root
        self.responseTokens = responseTokens; self.id = "mlx:\(repository)@\(revision)"
        self.supportsVision = supportsVision; self.weightBytes = weightBytes
    }

    private struct DownloadRecord: Codable {
        var repository: String
        var revision: String
        var relativeDirectory: String
    }
    private var recordURL: URL {
        let identity = SHA256.hash(data: Data((repository + "@" + revision).utf8)).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent("records").appendingPathComponent(identity + ".json")
    }
    func isDownloaded() -> Bool { (try? savedDirectory()) != nil }

    func download(allowCellular: Bool, expectedFiles: [LocalModelCatalogEntry.File] = [], progress: @Sendable @escaping (Double) -> Void) async throws {
        guard !busy, !downloadBusy else { throw AssistantError.busy }
        downloadBusy = true; defer { downloadBusy = false }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: recordURL.deletingLastPathComponent(), withIntermediateDirectories: true)
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
        try verify(directory, expectedFiles: expectedFiles)
        let record = DownloadRecord(repository: repository, revision: revision,
                                    relativeDirectory: String(directory.standardizedFileURL.path.dropFirst(base.count)))
        try JSONEncoder().encode(record).write(to: recordURL, options: .atomic)
        // Download completion does not load GPU weights or switch the active conversation's model.
        progress(1)
    }

    func unload() throws {
        guard !busy else { throw AssistantError.busy }
        container = nil
        MLX.Memory.clearCache()
    }
    func importFolder(_ source: URL, expectedFiles: [LocalModelCatalogEntry.File], progress: @Sendable @escaping (Double) -> Void) async throws {
        guard !busy, !downloadBusy else { throw AssistantError.busy }
        downloadBusy = true; defer { downloadBusy = false }
        let required = expectedFiles.filter { !$0.name.hasPrefix("README") && !$0.name.hasPrefix("LICENSE") }
        guard !required.isEmpty else { throw AssistantError.provider("This catalog entry has no verified model package.") }
        let destination = root.appendingPathComponent("imports").appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let base = root.resolvingSymlinksInPath().path + "/"
        guard destination.resolvingSymlinksInPath().path.hasPrefix(base) else { throw AssistantError.provider("Invalid model import destination.") }
        var committed = false
        defer { if !committed { try? FileManager.default.removeItem(at: destination) } }
        let total = max(Int64(1), required.reduce(0) { $0 + $1.bytes })
        var copied: Int64 = 0
        var lastProgress = Date.distantPast
        for file in required {
            try Task.checkCancellation()
            let input = source.appendingPathComponent(file.name).resolvingSymlinksInPath()
            guard input.path.hasPrefix(source.resolvingSymlinksInPath().path + "/"),
                  let size = try? input.resourceValues(forKeys: [.fileSizeKey]).fileSize, Int64(size) == file.bytes else {
                throw AssistantError.provider("Choose the complete matching MLX model folder, including its tokenizer, configuration, and safetensors files. A GGUF file or a different model revision cannot be imported as this package.")
            }
            let target = destination.appendingPathComponent(file.name)
            guard target.standardizedFileURL.path.hasPrefix(destination.standardizedFileURL.path + "/") else { throw AssistantError.provider("Invalid model filename.") }
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard FileManager.default.createFile(atPath: target.path, contents: nil) else { throw AssistantError.provider("There is not enough space to import the model.") }
            let reader = try FileHandle(forReadingFrom: input), writer = try FileHandle(forWritingTo: target)
            do {
                var written: Int64 = 0
                while let chunk = try reader.read(upToCount: 1024 * 1024), !chunk.isEmpty {
                    try Task.checkCancellation()
                    written += Int64(chunk.count)
                    guard written <= file.bytes else { throw AssistantError.provider("A model file changed during import.") }
                    try writer.write(contentsOf: chunk); copied += Int64(chunk.count)
                    if Date().timeIntervalSince(lastProgress) >= 0.15 || copied == total {
                        progress(Double(copied) / Double(total)); lastProgress = Date()
                    }
                }
                try reader.close(); try writer.close()
            } catch { try? reader.close(); try? writer.close(); throw error }
        }
        try verify(destination, expectedFiles: required)
        let record = DownloadRecord(repository: repository, revision: revision,
                                    relativeDirectory: "imports/" + destination.lastPathComponent)
        try FileManager.default.createDirectory(at: recordURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(record).write(to: recordURL, options: .atomic)
        committed = true; progress(1)
    }

    private func loadFromDisk() async throws {
        if container != nil { return }
        let directory = try savedDirectory()
        guard ProcessInfo.processInfo.thermalState != .critical else { throw AssistantError.provider("The iPhone is too warm to load a model. Let it cool, or use ChatGPT for now.") }
        let available = Int64(os_proc_available_memory())
        guard weightBytes == 0 || available >= weightBytes else { throw AssistantError.provider("The selected model's weights exceed the memory currently available to this app. Release another loaded model or try again with more memory available. Your download is kept.") }
        MLX.Memory.cacheLimit = 32 * 1024 * 1024
        // Preserve upstream EOS tokens, tool format and reasoning parser when resolving a local package.
        if supportsVision {
            let factory = VLMModelFactory.shared
            var configuration = factory.configuration(id: repository)
            configuration.id = .directory(directory); configuration.tokenizerSource = .directory(directory)
            container = try await factory.loadContainer(from: DiskOnlyDownloader(), using: #huggingFaceTokenizerLoader(), configuration: configuration)
        } else {
            let factory = LLMModelFactory.shared
            var configuration = factory.configuration(id: repository)
            configuration.id = .directory(directory); configuration.tokenizerSource = .directory(directory)
            container = try await factory.loadContainer(from: DiskOnlyDownloader(), using: #huggingFaceTokenizerLoader(), configuration: configuration)
        }
    }

    private func savedDirectory() throws -> URL {
        let legacyURL = root.appendingPathComponent("selected-model.json")
        let source = FileManager.default.fileExists(atPath: recordURL.path) ? recordURL : legacyURL
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw AssistantError.provider("Download the selected model in Settings before using local chat.")
        }
        let record = try JSONDecoder().decode(DownloadRecord.self, from: Data(contentsOf: source))
        guard record.repository == repository, record.revision == revision else {
            throw AssistantError.provider("The selected model has not been downloaded. Open Settings to download it.")
        }
        let directory = root.appendingPathComponent(record.relativeDirectory).standardizedFileURL
        guard directory.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/"),
              FileManager.default.fileExists(atPath: directory.appendingPathComponent("config.json").path) else {
            throw AssistantError.provider("Invalid saved model location.")
        }
        return directory
    }
    private func verify(_ directory: URL, expectedFiles: [LocalModelCatalogEntry.File]) throws {
        for file in expectedFiles {
            try Task.checkCancellation()
            let url = directory.appendingPathComponent(file.name)
            // HF snapshots may use links into the same app-owned cache. Resolve against the entire model root.
            guard url.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/"),
                  let size = try url.resolvingSymlinksInPath().resourceValues(forKeys: [.fileSizeKey]).fileSize, Int64(size) == file.bytes else {
                throw AssistantError.provider("A downloaded model file is missing or incomplete. Retry the download to repair it.")
            }
            if let expected = file.sha256 {
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                var digest = SHA256()
                while let block = try handle.read(upToCount: 1024 * 1024), !block.isEmpty {
                    try Task.checkCancellation(); digest.update(data: block)
                }
                let observed = digest.finalize().map { String(format: "%02x", $0) }.joined()
                guard observed == expected else { throw AssistantError.provider("A model file failed its integrity check. Its download was not accepted.") }
            }
        }
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

private struct DiskOnlyDownloader: Downloader {
    func download(id: String, revision: String?, matching patterns: [String], useLatest: Bool,
                  progressHandler: @Sendable @escaping (Progress) -> Void) async throws -> URL {
        throw AssistantError.provider("An unexpected remote model component was requested. Import the complete verified model package before using it offline.")
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
