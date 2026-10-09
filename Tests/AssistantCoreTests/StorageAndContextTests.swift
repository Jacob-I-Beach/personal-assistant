import Foundation
import XCTest
@testable import AssistantCore

final class StorageAndContextTests: XCTestCase, @unchecked Sendable {
    func testLegacyImportPreservesOriginalAndDoesNotReimportOnRestart() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/test-data/" + UUID().uuidString)
        let folder = root.appendingPathComponent("conversations")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var legacy = Conversation(title: "Legacy")
        legacy.messages = [Message(role: .user, text: "Original evidence")]
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let original = try encoder.encode(legacy)
        let file = folder.appendingPathComponent(legacy.id.uuidString + ".json")
        try original.write(to: file)
        let store = try LocalStore(root: root)
        var imported = try await store.loadConversation(legacy.id)
        XCTAssertEqual(imported.messages.first?.text, "Original evidence")
        imported.title = "Updated in database"
        try await store.save(imported)
        let reopened = try LocalStore(root: root)
        let restored = try await reopened.loadConversation(legacy.id)
        XCTAssertEqual(restored.title, "Updated in database")
        XCTAssertEqual(try Data(contentsOf: file), original)
    }
    func testThousandMessagesRemainSearchableWhileContextIsBounded() async throws {
        let store = try makeTestStore()
        var conversation = Conversation(title: "Long history")
        conversation.messages = (0..<1000).map { Message(role: $0.isMultiple(of: 2) ? .user : .assistant, text: "Message \($0): " + String(repeating: "saved text ", count: 15)) }
        conversation.messages[4].text = "The original lighthouse color is burgundy."
        try await store.save(conversation)
        let matches = try await store.searchMessages("lighthouse burgundy", conversationID: conversation.id)
        XCTAssertEqual(matches.map(\.id), [conversation.messages[4].id])
        let selected = try ContextPlanner.select(conversation.messages, instructions: "fixture", tools: [], limits: .init(maximumTextBytes: 8000))
        XCTAssertGreaterThan(selected.omittedMessageCount, 900)
        XCTAssertEqual(selected.messages.first?.role, .user)
        XCTAssertEqual(selected.messages.last?.id, conversation.messages.last?.id)
        let restored = try await store.loadConversation(conversation.id)
        XCTAssertEqual(restored.messages.count, 1000)
    }
    func testRemovedOrChangedTextCannotReturnThroughSearch() async throws {
        let store = try makeTestStore()
        var conversation = Conversation()
        conversation.messages = [Message(role: .user, text: "oldsecret"), Message(role: .assistant, text: "obsolete")]
        try await store.save(conversation)
        conversation.messages[0].text = "corrected"
        conversation.messages.removeLast()
        try await store.save(conversation)
        let old = try await store.searchMessages("oldsecret")
        let removed = try await store.searchMessages("obsolete")
        XCTAssertTrue(old.isEmpty); XCTAssertTrue(removed.isEmpty)
        let corrected = try await store.searchMessages("corrected")
        XCTAssertEqual(corrected.count, 1)
    }
    func testMessageIdentityCollisionRollsBackConversationWrite() async throws {
        let store = try makeTestStore()
        var first = Conversation(title: "First")
        first.messages = [Message(role: .user, text: "kept")]
        try await store.save(first)
        var collision = Conversation(title: "Must roll back")
        collision.messages = first.messages
        do { try await store.save(collision); XCTFail("Cross-conversation message accepted") } catch {}
        let summaries = try await store.conversationSummaries()
        XCTAssertEqual(summaries.map(\.id), [first.id])
    }
    func testScriptToolProducesDurableArtifactAndHistoryReadsAreScoped() async throws {
        let store = try makeTestStore()
        let conversation = Conversation()
        try await store.save(conversation)
        let tools = AssistantTools(store: store, conversationID: conversation.id, captureIDs: [], sandbox: JavaScriptSandbox())
        let result = try await tools.execute(ToolCall(id: "script", name: "run_javascript", arguments: .object([
            "code": .string("return {result: 42, files: {'answer.txt':'42'}};"), "input_json": .string("null")
        ])))
        XCTAssertTrue(result.succeeded)
        let reopened = try LocalStore(root: store.root)
        let artifacts = try await reopened.artifacts(conversationID: conversation.id)
        XCTAssertEqual(artifacts.first?.content, "42")
        let denied = try await tools.execute(ToolCall(id: "read", name: "read_history", arguments: .object([
            "message_id": .string(UUID().uuidString), "offset": .string("0")
        ])))
        XCTAssertFalse(denied.succeeded)
    }
}
