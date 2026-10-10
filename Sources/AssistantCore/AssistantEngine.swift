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
                                    backend: any ModelBackend, containsHealthData: Bool = false, fileIDs: [UUID] = [], workspaceEnabled: Bool = false, additionalTools: [ToolDefinition] = [],
                                    additionalExecutor: (@Sendable (ToolCall) async throws -> ToolResult)? = nil) -> AsyncThrowingStream<AssistantEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.run(conversation: conversation, text: text, captureIDs: captureIDs,
                                       backend: backend, containsHealthData: containsHealthData, fileIDs: fileIDs, workspaceEnabled: workspaceEnabled, additionalTools: additionalTools,
                                       additionalExecutor: additionalExecutor, output: continuation)
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private func run(conversation original: Conversation, text: String, captureIDs: [UUID],
                     backend: any ModelBackend, containsHealthData: Bool, fileIDs: [UUID], workspaceEnabled: Bool, additionalTools: [ToolDefinition],
                     additionalExecutor: (@Sendable (ToolCall) async throws -> ToolResult)?,
                     output: AsyncThrowingStream<AssistantEvent, any Error>.Continuation) async throws {
        guard activeRun == nil else { throw AssistantError.busy }
        let runID = UUID(); activeRun = runID
        defer {
            if activeRun == runID {
                activeRun = nil
                let waiting = idleWaiters; idleWaiters = []
                for waiter in waiting { waiter.resume() }
            }
        }
        var containsHealthData = containsHealthData
        for id in fileIDs {
            let file = try await store.workspaceFile(id)
            if file.containsHealthData {
                guard file.conversationID == original.id else { throw AssistantError.invalidTool("Health-derived files can only be used in their original conversation.") }
                containsHealthData = true
            }
        }
        if let destination = backend.networkDestination {
            guard !original.networkDisabled, original.allowedNetworkDestinations.contains(destination) else { throw AssistantError.networkNotAuthorized }
            if containsHealthData || original.containsHealthData {
                guard original.allowedHealthDestinations.contains(destination) else { throw AssistantError.networkNotAuthorized }
            }
        }
        var conversation = original
        conversation.archivedAt = nil
        for id in captureIDs { _ = try await store.loadCapture(id) }
        let user = Message(role: .user, text: text, captureIDs: captureIDs, fileIDs: fileIDs, containsHealthData: containsHealthData,
                           containsLocalOnlyContext: original.networkDisabled)
        conversation.messages.append(user)
        if conversation.title == "New conversation" { conversation.title = String(text.prefix(65)) }
        try await store.save(conversation)
        output.yield(.conversation(conversation))
        let availableMemories = MemoryContext.eligible(try await store.memories(), conversationID: conversation.id, remote: backend.networkDestination != nil)
        var localOnlyContext = backend.networkDestination == nil && (availableMemories.contains { !$0.allowsConnectedModels } || conversation.messages.contains(where: \.containsLocalOnlyContext))
        let eligibleAttachments = conversation.messages.filter { backend.networkDestination == nil || !$0.containsLocalOnlyContext }
        let broker = AssistantTools(store: store, conversationID: conversation.id, captureIDs: Set(eligibleAttachments.flatMap(\.captureIDs)), sandbox: sandbox,
                                    memoryEnabled: !availableMemories.isEmpty, remote: backend.networkDestination != nil,
                                    artifactLocalOnly: localOnlyContext, healthData: conversation.containsHealthData,
                                    fileIDs: Set(eligibleAttachments.flatMap(\.fileIDs)), workspaceEnabled: workspaceEnabled,
                                    compactCatalog: backend.contextLimits.maximumTextBytes < 20_000,
                                    additionalDefinitions: additionalTools, additionalExecutor: additionalExecutor)
        var executedCallIDs = Set<String>()

        for _ in 0..<12 {
            try Task.checkCancellation()
            var request = try await request(for: conversation, tools: broker.definitions, limits: backend.contextLimits, remote: backend.networkDestination != nil, nativeFiles: backend.supportsFileInputs)
            localOnlyContext = localOnlyContext || request.containsLocalOnlyContext
            if localOnlyContext { await broker.protectLocalContext() }
            request.toolExecutor = { call in
                output.yield(.activity("Running \(call.name.replacingOccurrences(of: "_", with: " "))"))
                return try await broker.execute(call)
            }
            output.yield(.activity("Generating a response"))
            var assistant = Message(role: .assistant, text: "", state: .streaming, providerID: backend.id, containsHealthData: conversation.containsHealthData, containsLocalOnlyContext: localOnlyContext)
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
                    case .activity(let status): output.yield(.activity(status))
                    case .citations(let citations): assistant.citations = citations
                    case .toolCall(let call): assistant.toolCalls.append(call)
                    case .executedTool(let call, let result):
                        localOnlyContext = localOnlyContext || result.containsLocalOnlyContext == true
                        try applyHealthAuthorization(result, destination: backend.networkDestination, conversation: &conversation)
                        guard result.callID == call.id, result.name == call.name,
                              executedCallIDs.insert(call.id).inserted, executedCallIDs.count <= 24 else {
                            throw AssistantError.invalidTool("The native model returned an invalid tool receipt.")
                        }
                        assistant.toolCalls.append(call); assistant.state = .complete
                        conversation.messages[index] = assistant
                        conversation.messages.append(Message(role: .tool, text: try result.modelText(), state: result.succeeded ? .complete : .failed, toolCallID: call.id, containsHealthData: conversation.containsHealthData || result.containsHealthData == true, containsLocalOnlyContext: localOnlyContext))
                        assistant = Message(role: .assistant, text: "", state: .streaming, providerID: backend.id, containsHealthData: conversation.containsHealthData, containsLocalOnlyContext: localOnlyContext)
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
                guard !assistant.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !assistant.toolCalls.isEmpty else {
                    throw AssistantError.provider("The model finished without an answer. Your request and completed tool results are saved. Retry or choose another model.")
                }
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
                assistant.failureReason = assistant.state == .failed ? error.localizedDescription : nil
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
                guard executedCallIDs.insert(call.id).inserted, executedCallIDs.count <= 24 else {
                    throw AssistantError.invalidTool("The model repeated a tool-call identifier. Execution was stopped.")
                }
                output.yield(.activity("Running \(call.name.replacingOccurrences(of: "_", with: " "))"))
                let result = try await broker.execute(call)
                localOnlyContext = localOnlyContext || result.containsLocalOnlyContext == true
                try applyHealthAuthorization(result, destination: backend.networkDestination, conversation: &conversation)
                try Task.checkCancellation()
                conversation.messages.append(Message(role: .tool, text: try result.modelText(), state: result.succeeded ? .complete : .failed, toolCallID: call.id, containsHealthData: conversation.containsHealthData || result.containsHealthData == true, containsLocalOnlyContext: localOnlyContext))
                try await store.save(conversation)
                output.yield(.toolResult(result)); output.yield(.conversation(conversation))
            }
        }
        throw AssistantError.invalidTool("The model reached the tool-round limit. All completed results were saved.")
    }

    private func applyHealthAuthorization(_ result: ToolResult, destination: String?, conversation: inout Conversation) throws {
        guard result.containsHealthData == true, let destination else { return }
        guard conversation.allowedHealthDestinations.contains(destination) || result.authorizedHealthDestination == destination else {
            throw AssistantError.networkNotAuthorized
        }
        conversation.allowedHealthDestinations.insert(destination)
    }

    private func request(for conversation: Conversation, tools: [ToolDefinition], limits: ContextLimits, remote: Bool, nativeFiles: Bool) async throws -> ModelRequest {
        var inputs: [ModelInputMessage] = []
        let notes = try await store.memories()
        var instructions = AssistantInstructions.base + MemoryContext.instructions(notes, query: conversation.messages.last(where: { $0.role == .user })?.text ?? "",
            conversationID: conversation.id, remote: remote)
        instructions += "\nCurrent device time: \(ISO8601DateFormatter().string(from: Date())). Time zone: \(TimeZone.current.identifier)."
        if let folderID = conversation.folderID, let folder = try await store.folders().first(where: { $0.id == folderID }) {
            instructions += "\nUser-selected topic folder: \(folder.name). User's folder instructions: \(folder.instructions)"
        }
        let eligibleMessages = conversation.messages.filter { !remote || !$0.containsLocalOnlyContext }
        if eligibleMessages.count != conversation.messages.count {
            instructions += "\nSome earlier messages relied on on-device-only context and are withheld. Do not reconstruct them; request additional shared context if needed."
        }
        let selection = try ContextPlanner.select(eligibleMessages, instructions: instructions, tools: tools, limits: limits)
        let answeredIDs = Set(eligibleMessages.filter { $0.role == .tool }.compactMap(\.toolCallID))
        let validCallIDs = Set(eligibleMessages.flatMap(\.toolCalls).map(\.id)).intersection(answeredIDs)
        let directFileIDs = Set(selection.messages.reversed().flatMap(\.fileIDs).prefix(nativeFiles ? 2 : 0))
        var fileBytes = 0
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
            var files: [ModelFile] = []
            for id in message.fileIDs {
                if let file = try? await store.workspaceFile(id) {
                    normalized.text += "\n[Attached file \(id.uuidString): \(file.filename). Read with read_workspace kind=file. \(file.extractionNote)]"
                    let ext = URL(fileURLWithPath: file.filename).pathExtension.lowercased()
                    if directFileIDs.contains(id), ["pdf", "docx", "pptx", "xlsx", "csv", "tsv", "txt", "md", "json", "html", "xml", "py", "js", "swift"].contains(ext), fileBytes + file.byteCount <= 25 * 1024 * 1024 {
                        let url = try await store.workspaceFileURL(id)
                        let data = try Data(contentsOf: url)
                        guard data.count == file.byteCount else { throw AssistantError.provider("An attached original file changed on disk. Import it again before sharing.") }
                        files.append(ModelFile(filename: file.filename, mediaType: file.mediaType, data: data)); fileBytes += data.count
                        normalized.text += " [Original file included for this request. PDF page images may be available to a vision-capable model; other Office formats provide text/cached data.]"
                    }
                } else { normalized.text += "\n[An earlier attached file was removed from the Library.]" }
            }
            for id in message.captureIDs {
                let capture = try await store.loadCapture(id)
                if selection.imageCaptureIDs.contains(id) { images.append(ModelImage(captureID: id, jpeg: try await store.imageData(id))) }
                normalized.text += "\n[Attached capture \(id.uuidString), captured \(ISO8601DateFormatter().string(from: capture.capturedAt)). Use read_capture for its saved OCR/depth metadata.]"
            }
            inputs.append(ModelInputMessage(message: normalized, images: images, files: files))
        }
        let notice = selection.omittedMessageCount == 0 ? "" : "\n\(selection.omittedMessageCount) older messages are outside this working context. They remain saved and can be searched with search_history; do not invent their contents."
        var request = ModelRequest(instructions: instructions + notice, messages: inputs, tools: tools)
        request.containsLocalOnlyContext = !remote && (MemoryContext.eligible(notes, conversationID: conversation.id, remote: false).contains { !$0.allowsConnectedModels }
            || eligibleMessages.contains(where: \.containsLocalOnlyContext))
        return request
    }
}
