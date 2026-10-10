import XCTest
@testable import AssistantCore

final class ConversationBrowsingTests: XCTestCase, @unchecked Sendable {
    func testRecentBrowsingFindsHistoryWithoutKeywordsAndRespectsProtection() async throws {
        let store = try makeTestStore()
        var visible = Conversation(title: "Earlier project")
        visible.messages = [Message(role: .user, text: "We chose the useful approach")]
        var hidden = Conversation(title: "Private project"); hidden.networkDisabled = true
        hidden.messages = [Message(role: .user, text: "Private context")]
        var archived = Conversation(title: "Archived project"); archived.archivedAt = Date()
        var health = Conversation(title: "Health project"); health.messages = [Message(role: .user, text: "Protected context", containsHealthData: true)]
        for chat in [visible, hidden, archived, health] { try await store.save(chat) }
        let remote = try await store.browsableConversations(remote: true)
        XCTAssertEqual(remote.map(\.id), [visible.id])
        let messages = try await store.browseConversationMessages(visible.id, remote: true)
        XCTAssertEqual(messages.first?.text, "We chose the useful approach")
        do { _ = try await store.browseConversationMessages(hidden.id, remote: true); XCTFail("Protected chat was readable") } catch {}
        var edited = visible; edited.modelTitleOverride = "Conversation"; try await store.save(edited)
        let titles = try await store.browsableConversations(remote: true, query: "Earlier")
        XCTAssertTrue(titles.isEmpty, "Edited-away generated titles must not leak through browse filters.")
    }
    func testBrowsingRequiresWorkspacePermission() async throws {
        let store = try makeTestStore(), chat = Conversation()
        try await store.save(chat)
        let tools = AssistantTools(store: store, conversationID: chat.id, captureIDs: [], sandbox: JavaScriptSandbox())
        let result = try await tools.execute(ToolCall(id: "browse", name: "list_conversations", arguments: .object(["query": .string(""), "offset": .string("0")])))
        XCTAssertFalse(result.succeeded)
    }
}
