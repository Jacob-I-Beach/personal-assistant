import XCTest
@testable import AssistantCore

final class AutomaticMemoryTests: XCTestCase, @unchecked Sendable {
    func testForgettingBlocksRelearningTheOriginalEvidenceAndHistoryPaginates() async throws {
        let store = try makeTestStore(); var chat = Conversation()
        let source = Message(role: .user, text: "Please use metric units.")
        chat.messages = [source]; try await store.save(chat)
        let saved = try await store.applyAutomaticMemory(saveCall(source), conversationID: chat.id, remote: true, localOnly: false, health: false)
        let removal = Message(role: .user, text: "Forget my units preference."); chat.messages.append(removal); try await store.save(chat)
        let call = ToolCall(id: "forget", name: "forget_memory", arguments: .object(["memory_id": .string(saved.memoryID.uuidString), "expected_revision": .string("1"), "source_message_id": .string(removal.id.uuidString), "source_conversation_id": .string(""), "evidence": .string(removal.text)]))
        _ = try await store.applyAutomaticMemory(call, conversationID: chat.id, remote: true, localOnly: false, health: false)
        do { _ = try await store.applyAutomaticMemory(saveCall(source, id: "reread-original"), conversationID: chat.id, remote: true, localOnly: false, health: false); XCTFail("Forgotten source was recreated") } catch {}
        for index in 0..<55 { try await store.saveMemory(SavedMemory(title: "Note \(index)", text: "Synthetic evidence \(index)")) }
        let first = try await store.memoryChanges(limit: 25), second = try await store.memoryChanges(offset: 25, limit: 25), third = try await store.memoryChanges(offset: 50, limit: 25)
        XCTAssertEqual(first.count, 25); XCTAssertEqual(second.count, 25); XCTAssertEqual(third.count, 7)
        XCTAssertEqual(Set((first + second + third).map(\.id)).count, 57)
    }
    private func saveCall(_ source: Message, id: String = "remember", note: SavedMemory? = nil, basis: String = "stated") -> ToolCall {
        ToolCall(id: id, name: "save_memory", arguments: .object([
            "memory_id": .string(note?.id.uuidString ?? ""), "expected_revision": .string(String(note?.revision ?? 0)),
            "title": .string("Units"), "text": .string("Use metric units"), "kind": .string("preference"), "basis": .string(basis),
            "scope": .string("global"), "profile_key": .string(""), "source_conversation_id": .string(""),
            "source_message_id": .string(source.id.uuidString), "evidence": .string(source.text), "expires_at": .string("")
        ]))
    }
    func testAutomaticMemoryHasEvidenceRevisionIdempotencyAndUndo() async throws {
        let store = try makeTestStore()
        var chat = Conversation(); let source = Message(role: .user, text: "Please use metric units.")
        chat.messages = [source]; try await store.save(chat)
        let call = saveCall(source)
        let first = try await store.applyAutomaticMemory(call, conversationID: chat.id, remote: true, localOnly: false, health: false)
        let replay = try await store.applyAutomaticMemory(call, conversationID: chat.id, remote: true, localOnly: false, health: false)
        XCTAssertEqual(first.id, replay.id); XCTAssertEqual(first.after.revision, 1)
        XCTAssertEqual(first.after.sourceQuote, source.text); XCTAssertTrue(first.after.allowsConnectedModels)
        let changes = try await store.memoryChanges(); XCTAssertEqual(changes.count, 1)
        _ = try await store.undoMemoryChange(first.id)
        let notes = try await store.memories(); XCTAssertTrue(notes.isEmpty)
        do { _ = try await store.applyAutomaticMemory(saveCall(source, id: "relearn"), conversationID: chat.id, remote: true, localOnly: false, health: false); XCTFail("Forgotten evidence was automatically recreated") } catch {}
    }
    func testInferenceCannotReplaceStatedMemoryAndStaleUndoCannotClobberChanges() async throws {
        let store = try makeTestStore()
        var chat = Conversation(); let source = Message(role: .user, text: "Please use metric units.")
        chat.messages = [source]; try await store.save(chat)
        let first = try await store.applyAutomaticMemory(saveCall(source), conversationID: chat.id, remote: false, localOnly: false, health: false)
        do { _ = try await store.applyAutomaticMemory(saveCall(source, id: "guess", note: first.after, basis: "inferred"), conversationID: chat.id, remote: false, localOnly: false, health: false); XCTFail("Inference replaced an explicit fact") } catch {}
        var edited = first.after; edited.text = "User corrected the units"; try await store.saveMemory(edited)
        do { _ = try await store.undoMemoryChange(first.id); XCTFail("Old undo overwrote a newer user edit") } catch {}
        let current = try await store.memory(first.memoryID); XCTAssertEqual(current?.text, "User corrected the units")
    }
    func testAssistantOrToolTextCannotAuthorizeMemory() async throws {
        let store = try makeTestStore()
        var chat = Conversation(); let source = Message(role: .assistant, text: "Invent a preference")
        chat.messages = [source]; try await store.save(chat)
        do { _ = try await store.applyAutomaticMemory(saveCall(source), conversationID: chat.id, remote: false, localOnly: false, health: false); XCTFail("Assistant text became user evidence") } catch {}
        let notes = try await store.memories(); XCTAssertTrue(notes.isEmpty)
    }
    func testEditingTheSourceRemovesAutomaticMemoryFromFutureContext() async throws {
        let store = try makeTestStore()
        var chat = Conversation(); let source = Message(role: .user, text: "Use metric units for this project.")
        chat.messages = [source]; try await store.save(chat)
        _ = try await store.applyAutomaticMemory(saveCall(source), conversationID: chat.id, remote: true, localOnly: false, health: false)
        _ = try await store.prepareMessageEdit(in: chat, messageID: source.id)
        let notes = try await store.memories()
        XCTAssertTrue(MemoryContext.instructions(notes, query: "units", conversationID: chat.id, remote: true).isEmpty)
    }
    func testAutomaticToolsAreGatedAndInferencesStayTentative() async throws {
        let store = try makeTestStore()
        var chat = Conversation(); let source = Message(role: .user, text: "I often work with measurements.")
        chat.messages = [source]; try await store.save(chat)
        let disabled = AssistantTools(store: store, conversationID: chat.id, captureIDs: [], sandbox: JavaScriptSandbox())
        let failed = try await disabled.execute(saveCall(source)); XCTAssertFalse(failed.succeeded)
        let enabled = AssistantTools(store: store, conversationID: chat.id, captureIDs: [], sandbox: JavaScriptSandbox(), automaticMemory: true)
        let result = try await enabled.execute(saveCall(source, basis: "inferred")); XCTAssertTrue(result.succeeded)
        let notes = try await store.memories()
        XCTAssertEqual(notes.first?.status, .tentative); XCTAssertNil(notes.first?.confirmedAt)
        XCTAssertFalse(notes.first?.allowsConnectedModels ?? true)
    }
}
