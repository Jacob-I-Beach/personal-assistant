import Foundation
import XCTest
@testable import AssistantCore

final class MemoryTests: XCTestCase, @unchecked Sendable {
    func testMemoryDestinationAndConversationBoundaries() {
        let current = UUID(), other = UUID()
        let local = SavedMemory(title: "Private note", text: "on-device secret")
        let shared = SavedMemory(title: "Preference", text: "Use metric units", allowsConnectedModels: true)
        let scoped = SavedMemory(title: "Other project", text: "outside scope", conversationID: other, allowsConnectedModels: true)
        let instructions = MemoryContext.instructions([local, shared, scoped], query: "units", conversationID: current, remote: true)
        XCTAssertTrue(instructions.contains("metric"))
        XCTAssertFalse(instructions.contains("secret")); XCTAssertFalse(instructions.contains("outside scope"))
        XCTAssertTrue(MemoryContext.instructions([local], query: "", conversationID: current, remote: false).contains("secret"))
    }
    func testEditsAndRemovalDoNotRetainOldMemoryInFutureContext() async throws {
        let store = try makeTestStore()
        var note = SavedMemory(title: "Preference", text: "Use the old preference")
        try await store.saveMemory(note)
        note.text = "Use the corrected preference"
        try await store.saveMemory(note)
        let notes = try await store.memories()
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.text, "Use the corrected preference")
        try await store.removeMemory(note.id)
        let remaining = try await store.memories()
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertTrue(MemoryContext.instructions(remaining, query: "preference", conversationID: UUID(), remote: false).isEmpty)
    }
    func testProtectedHistoryCannotBeRetrievedByAConnectedModel() async throws {
        let store = try makeTestStore()
        var conversation = Conversation()
        let secret = Message(role: .assistant, text: "privatevioletcode", containsLocalOnlyContext: true)
        conversation.messages = [secret, Message(role: .assistant, text: "publicvioletcode")]
        try await store.save(conversation)
        let remote = try await store.searchMessages("privatevioletcode", conversationID: conversation.id, excludingLocalOnly: true)
        XCTAssertTrue(remote.isEmpty)
        let local = try await store.searchMessages("privatevioletcode", conversationID: conversation.id)
        XCTAssertEqual(local.count, 1)
        let broker = AssistantTools(store: store, conversationID: conversation.id, captureIDs: [], sandbox: JavaScriptSandbox(), remote: true)
        let result = try await broker.execute(ToolCall(id: "read", name: "read_history", arguments: .object(["message_id": .string(secret.id.uuidString), "offset": .string("0")])))
        XCTAssertFalse(result.succeeded)
    }
    func testModelSwitchWithholdsAnswersDerivedFromPrivateMemory() async throws {
        let store = try makeTestStore()
        try await store.saveMemory(SavedMemory(title: "Private", text: "violet-private-value"))
        let engine = AssistantEngine(store: store)
        var conversation = Conversation()
        let localRecorder = MemoryRequestRecorder()
        let local = MemoryRecordingBackend(id: "local", networkDestination: nil, recorder: localRecorder, answer: "violet-private-value")
        for try await event in engine.respond(conversation: conversation, text: "Read my saved note", captureIDs: [], backend: local) {
            if case .conversation(let updated) = event { conversation = updated }
        }
        XCTAssertTrue(localRecorder.request?.instructions.contains("violet-private-value") == true)
        XCTAssertTrue(conversation.messages.last?.containsLocalOnlyContext == true)
        conversation.allowedNetworkDestinations.insert("fixture-remote")
        let remoteRecorder = MemoryRequestRecorder()
        let remote = MemoryRecordingBackend(id: "remote", networkDestination: "fixture-remote", recorder: remoteRecorder, answer: "Public answer")
        for try await _ in engine.respond(conversation: conversation, text: "Continue with shared context", captureIDs: [], backend: remote) {}
        let request = try XCTUnwrap(remoteRecorder.request)
        XCTAssertFalse(request.instructions.contains("violet-private-value"))
        XCTAssertFalse(request.messages.contains { $0.message.text.contains("violet-private-value") })
        let persisted = try await store.loadConversation(conversation.id)
        XCTAssertTrue(persisted.messages.contains { $0.text == "violet-private-value" })
    }
}

private final class MemoryRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var value: ModelRequest?
    var request: ModelRequest? { lock.withLock { value } }
    func record(_ request: ModelRequest) { lock.withLock { value = request } }
}
private struct MemoryRecordingBackend: ModelBackend {
    let id: String
    let networkDestination: String?
    let recorder: MemoryRequestRecorder
    let answer: String
    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        recorder.record(request)
        return AsyncThrowingStream { output in output.yield(.textDelta(answer)); output.yield(.completed); output.finish() }
    }
}
