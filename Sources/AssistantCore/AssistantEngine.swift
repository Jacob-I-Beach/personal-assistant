import Foundation

public enum AssistantEvent: Sendable {
    case conversation(Conversation)
    case toolResult(ToolResult)
    case finished
}

/// One app-owned orchestration loop for every backend. No provider receives direct device authority.
public actor AssistantEngine {
    private let store: LocalStore
    private var activeRun: UUID?
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    public init(store: LocalStore) { self.store = store }

    /// Call after cancelling a consumer to wait for the last persistence checkpoint and cleanup.
    public func waitUntilIdle() async {
        guard activeRun != nil else { return }
        await withCheckedContinuation { idleWaiters.append($0) }
    }

    public nonisolated func respond(conversation: Conversation, text: String, captureIDs: [UUID],
                                    backend: any ModelBackend) -> AsyncThrowingStream<AssistantEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.run(conversation: conversation, text: text, captureIDs: captureIDs,
                                       backend: backend, output: continuation)
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private func run(conversation original: Conversation, text: String, captureIDs: [UUID],
                     backend: any ModelBackend, output: AsyncThrowingStream<AssistantEvent, any Error>.Continuation) async throws {
        guard activeRun == nil else { throw AssistantError.busy }
        let runID = UUID(); activeRun = runID
        defer {
            if activeRun == runID {
                activeRun = nil
                let waiting = idleWaiters; idleWaiters = []
                for waiter in waiting { waiter.resume() }
            }
        }
        if let destination = backend.networkDestination,
           !original.allowedNetworkDestinations.contains(destination) { throw AssistantError.networkNotAuthorized }
        var conversation = original
        for id in captureIDs { _ = try await store.loadCapture(id) }
        let user = Message(role: .user, text: text, captureIDs: captureIDs)
        conversation.messages.append(user)
        if conversation.title == "New conversation" { conversation.title = String(text.prefix(65)) }
        try await store.save(conversation)
        output.yield(.conversation(conversation))
        let broker = CaptureToolBroker(store: store, allowedCaptureIDs: conversation.attachedCaptureIDs)
        var executedCallIDs = Set<String>()

        for _ in 0..<6 {
            try Task.checkCancellation()
            let request = try await request(for: conversation)
            var assistant = Message(role: .assistant, text: "", state: .streaming, providerID: backend.id)
            conversation.messages.append(assistant)
            let index = conversation.messages.count - 1
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
                let result = await broker.execute(call)
                try Task.checkCancellation()
                conversation.messages.append(Message(role: .tool, text: try result.modelText(), toolCallID: call.id))
                try await store.save(conversation)
                output.yield(.toolResult(result)); output.yield(.conversation(conversation))
            }
        }
        throw AssistantError.invalidTool("The model reached the tool-round limit. All completed results were saved.")
    }

    private func request(for conversation: Conversation) async throws -> ModelRequest {
        var inputs: [ModelInputMessage] = []
        let answeredIDs = Set(conversation.messages.filter { $0.role == .tool }.compactMap(\.toolCallID))
        let validCallIDs = Set(conversation.messages.flatMap(\.toolCalls).map(\.id)).intersection(answeredIDs)
        for message in conversation.messages {
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
                images.append(ModelImage(captureID: id, jpeg: try await store.imageData(id)))
                normalized.text += "\n[Attached capture \(id.uuidString), captured \(ISO8601DateFormatter().string(from: capture.capturedAt)). Use read_capture for its saved OCR/depth metadata.]"
            }
            inputs.append(ModelInputMessage(message: normalized, images: images))
        }
        let tools = conversation.attachedCaptureIDs.isEmpty ? [] : [CaptureToolBroker.definition]
        return ModelRequest(instructions: AssistantInstructions.base, messages: inputs, tools: tools)
    }
}
