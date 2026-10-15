import AssistantCore
import Foundation
import FoundationModels

struct AppleModelReadiness: Sendable {
    let title: String
    let isAvailable: Bool
    let detail: String
}

struct AppleModelBackend: ModelBackend {
    enum Location: Sendable { case device, privateCloud }
    let location: Location
    var supportsContextCheckpoints: Bool { true }
    var id: String { location == .device ? "apple:on-device" : "apple:private-cloud-compute" }
    var networkDestination: String? { location == .privateCloud ? "apple-private-cloud-compute" : nil }
    var contextLimits: ContextLimits { location == .device ? .appleOnDevice : ContextLimits(maximumTextBytes: 48_000, maximumImages: 0) }

    static func readiness(_ location: Location) -> AppleModelReadiness {
        #if targetEnvironment(simulator)
        return .init(title: location == .device ? "Apple on this iPhone" : "Apple Private Cloud Compute", isAvailable: false, detail: "Apple model inference requires a supported physical device. Simulator tests use synthetic backends.")
        #else
        if location == .device {
            let model = SystemLanguageModel.default
            let title = model.variant.displayName
            switch model.availability {
            case .available: return .init(title: title, isAvailable: true, detail: "On this iPhone · Apple system model")
            case .unavailable(.deviceNotEligible): return .init(title: title, isAvailable: false, detail: "Apple Intelligence is unavailable on this device.")
            case .unavailable(.appleIntelligenceNotEnabled): return .init(title: title, isAvailable: false, detail: "Enable Apple Intelligence in Settings.")
            case .unavailable(.modelNotReady): return .init(title: title, isAvailable: false, detail: "Apple's model is still preparing.")
            default: return .init(title: title, isAvailable: false, detail: "Apple's model is currently unavailable.")
            }
        }
        // Only the entitlement-enabled build advertises direct PCC access. Consumer Siri access does not sign the app.
        guard Bundle.main.object(forInfoDictionaryKey: "AssistantPCCEnabled") as? Bool == true else {
            return .init(title: "Apple Private Cloud Compute", isAvailable: false, detail: "Requires Apple's PCC entitlement for this app.")
        }
        switch PrivateCloudComputeLanguageModel().availability {
        case .available: return .init(title: "Apple Private Cloud Compute", isAvailable: true, detail: "Apple cloud · subject to your available quota")
        default: return .init(title: "Apple Private Cloud Compute", isAvailable: false, detail: "Apple cloud intelligence is not ready for this app.")
        }
        #endif
    }

    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        AsyncThrowingStream { output in
            let task = Task {
                do {
                    let readiness = Self.readiness(location)
                    guard readiness.isAvailable else { throw AssistantError.provider(readiness.detail) }
                    guard request.messages.allSatisfy({ $0.images.isEmpty }) else {
                        throw AssistantError.provider("Use a vision-capable downloaded or connected model for images. Apple's selected text model can still read saved OCR through tools.")
                    }
                    let gate = AppleToolGate(executor: request.toolExecutor, resultText: request.toolResultText, output: output,
                                             initialBytes: try ContextPlanner.requestTextCost(request), workingBytes: request.isCompaction ? contextLimits.maximumTextBytes : contextLimits.workingTextBytes)
                    let tools = try request.tools.map { try AppleToolProxy(definition: $0, gate: gate) }
                    let session: LanguageModelSession
                    if location == .device {
                        session = try Self.session(model: SystemLanguageModel.default, request: request, tools: tools)
                    } else {
                        session = try Self.session(model: PrivateCloudComputeLanguageModel(), request: request, tools: tools)
                    }
                    // A saved tool output is never a new user prompt. Include it
                    // in the transcript and ask the fresh session to continue.
                    let latest = request.messages.last?.message.role == .user ? request.messages.last!.message.text : "Continue the user's request using the saved results. Do not repeat completed actions."
                    if location == .device {
                        let model = SystemLanguageModel.default
                        let transcriptTokens = try await model.tokenCount(for: session.transcript)
                        let promptTokens = try await model.tokenCount(for: latest)
                        let capacity = request.isCompaction ? model.contextSize : ContextReserve.working(in: model.contextSize)
                        guard transcriptTokens + promptTokens + 512 <= capacity else { throw AssistantError.contextCapacity }
                    }
                    var previous = ""
                    do {
                        for try await snapshot in session.streamResponse(to: latest) {
                            try Task.checkCancellation()
                            if await gate.needsRollover { output.yield(.contextWindowRollover); output.finish(); return }
                            let current = snapshot.content
                            guard current.hasPrefix(previous) else { throw AssistantError.malformedStream("Apple's response changed an already displayed prefix.") }
                            let delta = String(current.dropFirst(previous.count))
                            if !delta.isEmpty { output.yield(.textDelta(delta)) }
                            previous = current
                        }
                    } catch LanguageModelError.contextSizeExceeded {
                        guard await gate.completedCount > 0 else { throw AssistantError.contextCapacity }
                        output.yield(.contextWindowRollover); output.finish(); return
                    } catch {
                        if await gate.needsRollover { output.yield(.contextWindowRollover); output.finish(); return }
                        throw error
                    }
                    try Task.checkCancellation()
                    output.yield(.completed); output.finish()
                } catch { output.finish(throwing: error) }
            }
            output.onTermination = { @Sendable _ in task.cancel() }
        }
    }
    private static func session<M: LanguageModel>(model: M, request: ModelRequest, tools: [AppleToolProxy]) throws -> LanguageModelSession {
        let initial = LanguageModelSession(model: model, tools: tools, instructions: request.instructions)
        var entries = Array(initial.transcript)
        let messages = (request.messages.last?.message.role == .user ? Array(request.messages.dropLast()) : request.messages).map(\.message)
        let names = Dictionary(messages.flatMap(\.toolCalls).map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        for message in messages {
            let segments: [Transcript.Segment] = [.text(.init(content: message.text))]
            switch message.role {
            case .user: entries.append(.prompt(.init(id: message.id.uuidString, segments: segments)))
            case .assistant:
                if !message.text.isEmpty { entries.append(.response(.init(id: message.id.uuidString, assetIDs: [], segments: segments))) }
                if !message.toolCalls.isEmpty {
                    let calls = try message.toolCalls.map { call in
                        Transcript.ToolCall(id: call.id, toolName: call.name, arguments: try GeneratedContent(json: CompactToolInvocation.modelArguments(for: call).jsonString()))
                    }
                    entries.append(.toolCalls(.init(calls)))
                }
            case .tool:
                if let id = message.toolCallID, let name = names[id] { entries.append(.toolOutput(.init(id: id, toolName: name, segments: segments))) }
            }
        }
        return LanguageModelSession(model: model, tools: tools, transcript: Transcript(entries: entries))
    }
}

private struct AppleToolProxy: Tool {
    typealias Arguments = GeneratedContent
    typealias Output = String
    let name: String
    let description: String
    let parameters: GenerationSchema
    let gate: AppleToolGate
    init(definition: AssistantCore.ToolDefinition, gate: AppleToolGate) throws {
        name = definition.name; description = definition.description; self.gate = gate
        parameters = try AppleToolSchema.make(definition)
    }
    func call(arguments: GeneratedContent) async throws -> String {
        guard arguments.isComplete else { throw AssistantError.invalidTool("Apple supplied incomplete tool arguments.") }
        return try await gate.execute(ToolCall(id: UUID().uuidString, name: name, arguments: JSONValue.parse(arguments.jsonString)))
    }
}
private enum AppleCheckpointBoundary: Error { case reached }
private actor AppleToolGate {
    let executor: (@Sendable (AssistantCore.ToolCall) async throws -> ToolResult)?
    let resultText: (@Sendable (ToolResult) throws -> String)?
    let output: AsyncThrowingStream<ModelEvent, any Error>.Continuation
    var count = 0
    var completedCount = 0
    var usedBytes: Int
    let workingBytes: Int
    var needsRollover = false
    init(executor: (@Sendable (AssistantCore.ToolCall) async throws -> ToolResult)?, resultText: (@Sendable (ToolResult) throws -> String)?, output: AsyncThrowingStream<ModelEvent, any Error>.Continuation, initialBytes: Int, workingBytes: Int) {
        self.executor = executor; self.resultText = resultText; self.output = output
        self.usedBytes = initialBytes; self.workingBytes = workingBytes
    }
    func execute(_ call: AssistantCore.ToolCall) async throws -> String {
        try Task.checkCancellation()
        guard !needsRollover else { throw AppleCheckpointBoundary.reached }
        guard count < 12, let executor else { throw AssistantError.invalidTool("This Apple model session reached its tool limit.") }
        count += 1
        let result = try await executor(call)
        completedCount += 1
        output.yield(.executedTool(call, result))
        let text = try resultText?(result) ?? result.modelText()
        usedBytes += text.utf8.count + (try call.arguments.jsonString()).utf8.count + 200
        if usedBytes >= workingBytes { needsRollover = true; throw AppleCheckpointBoundary.reached }
        return text
    }
}
