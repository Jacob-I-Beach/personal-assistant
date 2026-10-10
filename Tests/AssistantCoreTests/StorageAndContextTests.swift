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

    func testFailedScriptCannotBeReplacedWithAnInventedArtifactAndCanRecover() async throws {
        let store = try makeTestStore(), conversation = Conversation()
        try await store.save(conversation)
        let tools = AssistantTools(store: store, conversationID: conversation.id, captureIDs: [], sandbox: JavaScriptSandbox())
        let failed = try await tools.execute(ToolCall(id: "failed-script", name: "run_javascript", arguments: .object([
            "code": .string("throw new Error('fixture failure');"), "input_json": .string("null")
        ])))
        XCTAssertFalse(failed.succeeded)
        XCTAssertEqual(try JSONValue.parse(failed.modelText())["tool_succeeded"], .bool(false))
        let invented = try await tools.execute(ToolCall(id: "invented-file", name: "create_artifact", arguments: .object([
            "filename": .string("totals.csv"), "content": .string("value\n18.5\n27.25\n14.75\n61.55")
        ])))
        XCTAssertFalse(invented.succeeded)
        let beforeRecovery = try await store.artifacts(conversationID: conversation.id)
        XCTAssertTrue(beforeRecovery.isEmpty)
        let recovered = try await tools.execute(ToolCall(id: "recovered-script", name: "run_javascript", arguments: .object([
            "code": .string("""
            const values = input.values;
            const total = values.reduce((sum, value) => sum + value, 0);
            const csv = 'value\\n' + [...values, total].join('\\n') + '\\n';
            return {result: total, files: {'totals.csv': csv}};
            """), "input_json": .string("{\"values\":[18.5,27.25,14.75]}")
        ])))
        XCTAssertTrue(recovered.succeeded); XCTAssertEqual(recovered.output["result"], .number(60.5))
        let reopened = try LocalStore(root: store.root)
        let artifacts = try await reopened.artifacts(conversationID: conversation.id)
        XCTAssertEqual(artifacts.map(\.content), ["value\n18.5\n27.25\n14.75\n60.5\n"])
        XCTAssertEqual(artifacts.first?.sourceCallID, "recovered-script")
        let note = try await tools.execute(ToolCall(id: "after-recovery", name: "create_artifact", arguments: .object([
            "filename": .string("notes.md"), "content": .string("A successful calculation is available.")
        ])))
        XCTAssertTrue(note.succeeded)
    }

    func testJSONRenamedToCSVIsRejectedAndToolFailuresRemainVisible() async throws {
        let store = try makeTestStore(), conversation = Conversation()
        try await store.save(conversation)
        let tools = AssistantTools(store: store, conversationID: conversation.id, captureIDs: [], sandbox: JavaScriptSandbox())
        let result = try await tools.execute(ToolCall(id: "mislabelled", name: "create_artifact", arguments: .object([
            "filename": .string("totals.csv"), "content": .string("[18.5,27.25,14.75,61.55]")
        ])))
        XCTAssertFalse(result.succeeded)
        let legacy = Message(role: .tool, text: "{\"error\":\"fixture failure\"}")
        XCTAssertEqual(legacy.toolFailureDescription, "fixture failure")
        let saved = Message(role: .tool, text: try result.modelText(), state: .failed)
        XCTAssertNotNil(saved.toolFailureDescription)
        let roundTrip = try JSONDecoder().decode(Message.self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(roundTrip.toolFailureDescription, saved.toolFailureDescription)
        let success = Message(role: .tool, text: "{\"result\":{\"error\":\"ordinary data\"},\"tool_succeeded\":true}")
        XCTAssertNil(success.toolFailureDescription)
    }

    func testOlderConcurrentScriptSuccessDoesNotClearANewerFailure() async {
        let status = ToolExecutionStatus()
        let first = await status.beginScript(), second = await status.beginScript()
        let whileRunning = await status.canAuthorArtifact
        XCTAssertFalse(whileRunning)
        await status.finishScript(second, succeeded: false)
        await status.finishScript(first, succeeded: true)
        let afterFailure = await status.canAuthorArtifact
        XCTAssertFalse(afterFailure)
        let retry = await status.beginScript()
        await status.finishScript(retry, succeeded: true)
        let recovered = await status.canAuthorArtifact
        XCTAssertTrue(recovered)
    }
}
