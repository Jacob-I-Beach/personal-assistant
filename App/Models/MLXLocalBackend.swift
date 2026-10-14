import AssistantCore
import CoreImage
import CryptoKit
import Foundation
import Darwin
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
    private nonisolated let textWeightBytes: Int64?
    private nonisolated let requestedContextTokens: Int?
    private nonisolated let requestedMemoryGiB: Int
    private nonisolated let footprint = LocalModelFootprint()
    nonisolated var residentBytes: Int64 { footprint.value }
    nonisolated var memoryBudget: LocalInferenceBudget { planningBudget(memoryGiB: requestedMemoryGiB, contextTokens: requestedContextTokens, availableBytes: Int64(os_proc_available_memory())) }
    nonisolated func planningBudget(memoryGiB: Int, contextTokens: Int?, availableBytes: Int64) -> LocalInferenceBudget {
        let vision = footprint.vision ?? (supportsVision && textWeightBytes == nil)
        return LocalInferenceBudget(weightBytes: vision ? weightBytes : (textWeightBytes ?? weightBytes), availableBytes: availableBytes, residentBytes: residentBytes,
            requestedMemoryGiB: memoryGiB, requestedContextTokens: contextTokens,
            responseTokens: responseTokens, supportsEfficientKV: repository.contains("Qwen3.5-4B"), optimizedTextRuntime: !vision && textWeightBytes != nil)
    }
    nonisolated var contextLimits: ContextLimits {
        ContextLimits(maximumTextBytes: max(4_096, memoryBudget.inputTokens * 3), maximumImages: footprint.vision == true ? 1 : 0)
    }
    private var container: ModelContainer?
    private var busy = false
    private var downloadBusy = false
    private var runtimeInitialized = false
    private var preparing = false
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    init(repository: String, revision: String, root: URL, responseTokens: Int, supportsVision: Bool = true, weightBytes: Int64 = 0, textWeightBytes: Int64? = nil,
         requestedContextTokens: Int? = nil, requestedMemoryGiB: Int = 8) {
        self.repository = repository; self.revision = revision; self.root = root
        self.responseTokens = responseTokens; self.id = "mlx:\(repository)@\(revision)"
        self.supportsVision = supportsVision; self.weightBytes = weightBytes
        self.textWeightBytes = textWeightBytes
        self.requestedContextTokens = requestedContextTokens; self.requestedMemoryGiB = requestedMemoryGiB
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
        let directory = try await ModelPackageDownload.download(repository: repository, revision: revision, root: root,
            files: expectedFiles, allowCellular: allowCellular, progress: progress)
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

    private func waitUntilIdle() async {
        while busy || preparing { await withCheckedContinuation { idleWaiters.append($0) } }
    }
    private func notifyIdle() {
        guard !busy, !preparing else { return }
        let waiting = idleWaiters; idleWaiters = []; waiting.forEach { $0.resume() }
    }
    func unload() async throws {
        await waitUntilIdle()
        container = nil
        footprint.set(0, vision: nil)
        // An unused backend must never initialize Metal merely to clear an empty cache,
        // especially after the app has already moved into the background.
        if runtimeInitialized { MLX.Memory.clearCache() }
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

    func prepareForResponse(containsImages: Bool) async throws {
        await waitUntilIdle()
        try Task.checkCancellation()
        try await loadFromDisk(containsImages: containsImages)
        guard memoryBudget.fits else {
            try await unload()
            throw AssistantError.provider("iOS did not leave enough working memory after the local model loaded. The model has been released and your request is saved. Check its memory details and retry when more headroom is available.")
        }
    }
    private func loadFromDisk(containsImages: Bool) async throws {
        let vision = supportsVision && (containsImages || textWeightBytes == nil)
        if container != nil, footprint.vision == vision { return }
        guard !preparing else { throw AssistantError.busy }
        preparing = true
        defer { preparing = false; notifyIdle() }
        // Only one representation is resident. Exclude vision tensors before
        // the upstream loader's parallel materialization, not just sanitation.
        if container != nil {
            container = nil; footprint.set(0, vision: nil)
            if runtimeInitialized { MLX.Memory.clearCache() }
        }
        let directory = try savedDirectory()
        guard ProcessInfo.processInfo.thermalState != .critical else { throw AssistantError.provider("The iPhone is too warm to load a model. Let it cool, or use ChatGPT for now.") }
        let plan = LocalInferenceBudget(weightBytes: vision ? weightBytes : (textWeightBytes ?? weightBytes), availableBytes: Int64(os_proc_available_memory()),
            requestedMemoryGiB: requestedMemoryGiB, requestedContextTokens: requestedContextTokens, responseTokens: responseTokens,
            supportsEfficientKV: repository.contains("Qwen3.5-4B"), optimizedTextRuntime: !vision && textWeightBytes != nil)
        guard plan.fits else {
            throw AssistantError.provider(vision && textWeightBytes != nil
                ? "This image request needs Qwen's larger vision runtime, which does not fit the iPhone's current memory headroom. The same downloaded model can run text chats with less memory. Your image and request are saved."
                : "The selected local runtime needs more memory headroom before it can load. Your request and download are saved. Check this model's details or release another loaded model, then retry.")
        }
        var loadDirectory = directory
        if !vision, let textWeightBytes {
            let identity = SHA256.hash(data: Data((repository + "@" + revision).utf8)).map { String(format: "%02x", $0) }.joined()
            loadDirectory = root.appendingPathComponent("text-runtime").appendingPathComponent(identity)
            _ = try await TextModelWeights.prepareAsync(source: directory.appendingPathComponent("model.safetensors"),
                destination: loadDirectory.appendingPathComponent("model.safetensors"), expectedPayloadBytes: textWeightBytes)
            for name in ["config.json", "generation_config.json"] {
                let original = directory.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: original.path) {
                    try Data(contentsOf: original).write(to: loadDirectory.appendingPathComponent(name), options: .atomic)
                }
            }
        }
        try Task.checkCancellation()
        runtimeInitialized = true
        MLX.Memory.cacheLimit = 8 * 1024 * 1024
        MLX.Memory.clearCache()
        MLX.Memory.memoryLimit = Int(plan.workingBytes)
        let before = LocalProcessMemory.footprint
        // Preserve upstream EOS tokens, tool format and reasoning parser when resolving a local package.
        if vision {
            let factory = VLMModelFactory.shared
            let configuration = Self.diskConfiguration(factory.configuration(id: repository), directory: loadDirectory, tokenizerDirectory: directory)
            container = try await factory.loadContainer(from: DiskOnlyDownloader(), using: #huggingFaceTokenizerLoader(), configuration: configuration)
        } else {
            let factory = LLMModelFactory.shared
            let configuration = Self.diskConfiguration(factory.configuration(id: repository), directory: loadDirectory, tokenizerDirectory: directory)
            container = try await factory.loadContainer(from: DiskOnlyDownloader(), using: #huggingFaceTokenizerLoader(), configuration: configuration)
        }
        do { try Task.checkCancellation() } catch {
            container = nil; MLX.Memory.clearCache(); throw error
        }
        let processGrowth = max(0, LocalProcessMemory.footprint - before)
        footprint.set(max(Int64(MLX.Memory.activeMemory), processGrowth), vision: vision)
    }

    private static func diskConfiguration(_ source: ModelConfiguration, directory: URL, tokenizerDirectory: URL) -> ModelConfiguration {
        var result = ModelConfiguration(directory: directory, tokenizerSource: .directory(tokenizerDirectory),
            defaultPrompt: source.defaultPrompt, extraEOSTokens: source.extraEOSTokens,
            stopStrings: source.stopStrings, eosTokenIds: source.eosTokenIds,
            toolCallFormat: source.toolCallFormat, reasoningConfig: source.reasoningConfig,
            messageGenerator: source.messageGenerator)
        result.weightFileSelection = source.weightFileSelection
        return result
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
                guard observed == expected else {
                    try? FileManager.default.removeItem(at: url)
                    throw AssistantError.provider("A model file failed verification and was removed. Tap Download to repair that file; the other completed files are kept.")
                }
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
        guard !busy, !preparing else { throw AssistantError.busy }
        busy = true; defer { busy = false; notifyIdle() }
        if !request.isMetadata || container == nil { try await loadFromDisk(containsImages: request.messages.contains { !$0.images.isEmpty }) }
        guard let container else { throw AssistantError.provider("The local model did not load.") }
        var messages: [Chat.Message] = [.system(request.instructions)]
        for entry in request.messages {
            let m = entry.message
            let images: [UserInput.Image] = try entry.images.map { image in
                guard let value = CIImage(data: image.jpeg) else { throw AssistantError.invalidCapture("The attached image cannot be decoded.") }
                // Bound vision preprocessing independently from context tokens.
                let dimension = max(value.extent.width, value.extent.height)
                guard dimension.isFinite, dimension > 0 else { throw AssistantError.invalidCapture("This image has invalid dimensions.") }
                let scale = min(1, 1024 / dimension)
                return .ciImage(value.transformed(by: CGAffineTransform(scaleX: scale, y: scale)), label: image.captureID.uuidString)
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
        let budget = memoryBudget
        guard budget.fits else { throw AssistantError.provider("Available memory changed. Release the local model and try a smaller working context.") }
        let tokenCount = try await container.perform(nonSendable: UserInput(chat: messages,
            tools: specs.isEmpty ? nil : specs, additionalContext: ["enable_thinking": false])) { context, input in
                let prepared = try await context.processor.prepare(input: input)
                return prepared.text.tokens.size
            }
        guard tokenCount <= budget.inputTokens else { throw AssistantError.contextCapacity }
        let parameters = GenerateParameters(maxTokens: budget.responseTokens, kvBits: budget.attentionCacheBits,
            kvGroupSize: 64, quantizedKVStart: 0, temperature: 0.4,
            prefill: .init(stepSize: ProcessInfo.processInfo.thermalState == .serious ? 16 : 32))
        let session = ChatSession(container, generateParameters: parameters,
                                  additionalContext: ["enable_thinking": false], tools: specs.isEmpty ? nil : specs)
        var calls: [AssistantCore.ToolCall] = []
        var stoppedNormally = false
        for try await event in session.streamDetails(to: messages) {
            try Task.checkCancellation()
            if ProcessInfo.processInfo.thermalState == .critical || os_proc_available_memory() < 192 * 1_024 * 1_024 {
                throw AssistantError.provider("Local generation paused to protect the iPhone's available memory or temperature. Your chat and model download are kept.")
            }
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

private final class LocalModelFootprint: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes: Int64 = 0
    private var includesVision: Bool?
    var value: Int64 { lock.withLock { bytes } }
    var vision: Bool? { lock.withLock { includesVision } }
    func set(_ value: Int64, vision: Bool?) { lock.withLock { bytes = value; includesVision = vision } }
}

/// Includes CPU tokenizer and model-loading allocations that MLX's GPU-only
/// activeMemory counter cannot see. No elevated memory grant is assumed.
private enum LocalProcessMemory {
    static var footprint: Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int64(info.phys_footprint) : 0
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
