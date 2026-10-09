import Foundation

public enum AssistantEvent: Sendable {
    case conversation(Conversation)
    case toolResult(ToolResult)
    case activity(String)
    case finished
}

/// One app-owned orchestration loop for every backend. No provider receives direct device authority.
public actor AssistantEngine {
    private let store: LocalStore
    private let sandbox = JavaScriptSandbox()
    private var activeRun: UUID?
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    public init(store: LocalStore) { self.store = store }

    /// Call after cancelling a consumer to wait for the last persistence checkpoint and cleanup.
    public func waitUntilIdle() async {
        guard activeRun != nil else { return }
        await withCheckedContinuation { idleWaiters.append($0) }
    }

    public nonisolated func respond(conversation: Conversation, text: String, captureIDs: [UUID],
                                    backend: any ModelBackend, containsHealthData: Bool = false) -> AsyncThrowingStream<AssistantEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.run(conversation: conversation, text: text, captureIDs: captureIDs,
                                       backend: backend, containsHealthData: containsHealthData, output: continuation)
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private func run(conversation original: Conversation, text: String, captureIDs: [UUID],
                     backend: any ModelBackend, containsHealthData: Bool, output: AsyncThrowingStream<AssistantEvent, any Error>.Continuation) async throws {
        guard activeRun == nil else { throw AssistantError.busy }
        let runID = UUID(); activeRun = runID
        defer {
            if activeRun == runID {
                activeRun = nil
                let waiting = idleWaiters; idleWaiters = []
                for waiter in waiting { waiter.resume() }
            }
        }
        if let destination = backend.networkDestination {
            guard !original.networkDisabled, original.allowedNetworkDestinations.contains(destination) else { throw AssistantError.networkNotAuthorized }
            if containsHealthData || original.containsHealthData {
                guard original.allowedHealthDestinations.contains(destination) else { throw AssistantError.networkNotAuthorized }
            }
        }
        var conversation = original
        for id in captureIDs { _ = try await store.loadCapture(id) }
        let user = Message(role: .user, text: text, captureIDs: captureIDs, containsHealthData: containsHealthData)
        conversation.messages.append(user)
        if conversation.title == "New conversation" { conversation.title = String(text.prefix(65)) }
        try await store.save(conversation)
        output.yield(.conversation(conversation))
        let broker = AssistantTools(store: store, conversationID: conversation.id, captureIDs: conversation.attachedCaptureIDs, sandbox: sandbox)
        var executedCallIDs = Set<String>()

        for _ in 0..<6 {
            try Task.checkCancellation()
            var request = try await request(for: conversation, tools: broker.definitions, limits: backend.contextLimits)
            request.toolExecutor = { call in
                output.yield(.activity("Running \(call.name.replacingOccurrences(of: "_", with: " "))"))
                return try await broker.execute(call)
            }
            output.yield(.activity("Generating a response"))
            var assistant = Message(role: .assistant, text: "", state: .streaming, providerID: backend.id, containsHealthData: conversation.containsHealthData)
            conversation.messages.append(assistant)
            var index = conversation.messages.count - 1
            try await store.save(conversation)
            output.yield(.conversation(conversation))
            var completed = false
            var lastCheckpoint = Date()
            do {
                for try await event in backend.stream(request) {
                    try Task.checkCancellation()
                    switch event {
                    case .textDelta(let text): assistant.text += text
                    case .toolCall(let call): assistant.toolCalls.append(call)
                    case .executedTool(let call, let result):
                        guard result.callID == call.id, result.name == call.name,
                              executedCallIDs.insert(call.id).inserted, executedCallIDs.count <= 24 else {
                            throw AssistantError.invalidTool("The native model returned an invalid tool receipt.")
                        }
                        assistant.toolCalls.append(call); assistant.state = .complete
                        conversation.messages[index] = assistant
                        conversation.messages.append(Message(role: .tool, text: try result.modelText(), toolCallID: call.id, containsHealthData: conversation.containsHealthData))
                        assistant = Message(role: .assistant, text: "", state: .streaming, providerID: backend.id, containsHealthData: conversation.containsHealthData)
                        conversation.messages.append(assistant); index = conversation.messages.count - 1
                        try await store.save(conversation)
                        output.yield(.toolResult(result))
                    case .continuation(let items): assistant.continuation = ProviderContinuation(providerID: backend.id, items: items)
                    case .completed: completed = true
                    }
                    conversation.messages[index] = assistant
                    output.yield(.conversation(conversation))
                    if Date().timeIntervalSince(lastCheckpoint) >= 1 {
                        try await store.save(conversation); lastCheckpoint = Date()
                    }
                }
                try Task.checkCancellation()
                guard completed else { throw AssistantError.incompleteResponse }
                guard assistant.toolCalls.count <= 16,
                      Set(assistant.toolCalls.map(\.id)).count == assistant.toolCalls.count else {
                    throw AssistantError.invalidTool("The model returned duplicate or too many tool calls. None were executed.")
                }
                assistant.state = .complete
                conversation.messages[index] = assistant
                try await store.save(conversation)
                output.yield(.conversation(conversation))
            } catch {
                assistant.state = Task.isCancelled || error is CancellationError ? .interrupted : .failed
                // Partial tool calls have never been executed and must not be replayed as completed calls.
                assistant.toolCalls = []; assistant.continuation = nil
                conversation.messages[index] = assistant
                try await store.save(conversation)
                output.yield(.conversation(conversation))
                throw error
            }
            if assistant.toolCalls.isEmpty { output.yield(.finished); return }
            for call in assistant.toolCalls {
                try Task.checkCancellation()
                guard executedCallIDs.insert(call.id).inserted else {
                    throw AssistantError.invalidTool("The model repeated a tool-call identifier. Execution was stopped.")
                }
                output.yield(.activity("Running \(call.name.replacingOccurrences(of: "_", with: " "))"))
                let result = try await broker.execute(call)
                try Task.checkCancellation()
                conversation.messages.append(Message(role: .tool, text: try result.modelText(), toolCallID: call.id, containsHealthData: conversation.containsHealthData))
                try await store.save(conversation)
                output.yield(.toolResult(result)); output.yield(.conversation(conversation))
            }
        }
        throw AssistantError.invalidTool("The model reached the tool-round limit. All completed results were saved.")
    }

    private func request(for conversation: Conversation, tools: [ToolDefinition], limits: ContextLimits) async throws -> ModelRequest {
        var inputs: [ModelInputMessage] = []
        let selection = try ContextPlanner.select(conversation.messages, instructions: AssistantInstructions.base, tools: tools, limits: limits)
        let answeredIDs = Set(conversation.messages.filter { $0.role == .tool }.compactMap(\.toolCallID))
        let validCallIDs = Set(conversation.messages.flatMap(\.toolCalls).map(\.id)).intersection(answeredIDs)
        for message in selection.messages {
            if message.role == .tool, !validCallIDs.contains(message.toolCallID ?? "") { continue }
            // Incomplete assistant text can be useful context, but unexecuted calls must never be reissued from disk.
            var normalized = message
            if normalized.state != .complete { normalized.toolCalls = []; normalized.continuation = nil }
            let completedCalls = normalized.toolCalls.filter { validCallIDs.contains($0.id) }
            if completedCalls.count != normalized.toolCalls.count {
                normalized.toolCalls = completedCalls
                normalized.continuation = nil
                normalized.text += "\n[An earlier tool request was interrupted before a saved result. Do not assume it completed.]"
            }
            var images: [ModelImage] = []
            for id in message.captureIDs {
                let capture = try await store.loadCapture(id)
                if selection.imageCaptureIDs.contains(id) { images.append(ModelImage(captureID: id, jpeg: try await store.imageData(id))) }
                normalized.text += "\n[Attached capture \(id.uuidString), captured \(ISO8601DateFormatter().string(from: capture.capturedAt)). Use read_capture for its saved OCR/depth metadata.]"
            }
            inputs.append(ModelInputMessage(message: normalized, images: images))
        }
        let notice = selection.omittedMessageCount == 0 ? "" : "\n\(selection.omittedMessageCount) older messages are outside this working context. They remain saved and can be searched with search_history; do not invent their contents."
        return ModelRequest(instructions: AssistantInstructions.base + notice, messages: inputs, tools: tools)
    }
}
