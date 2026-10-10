import Foundation
import XCTest
@testable import AssistantCore

final class FolderTests: XCTestCase, @unchecked Sendable {
    func testMoveRenameArchiveAndFolderRemovalPreserveConversationContents() async throws {
        let store = try makeTestStore(), folder = ChatFolder(name: "Projects")
        try await store.saveFolder(folder)
        var conversation = Conversation(title: "Original")
        conversation.messages = [Message(role: .user, text: "Distinctive project record")]
        try await store.save(conversation)
        let original = try await store.loadConversation(conversation.id)
        try await store.moveConversation(conversation.id, to: folder.id)
        try await store.renameConversation(conversation.id, title: "New title")
        try await store.setArchived(conversation.id, archived: true)
        let hidden = try await store.searchMessages("Distinctive")
        XCTAssertTrue(hidden.isEmpty)
        let archived = try await store.searchMessages("Distinctive", includeArchived: true)
        XCTAssertEqual(archived.count, 1)
        try await store.removeFolder(folder.id)
        let saved = try await store.loadConversation(conversation.id)
        XCTAssertNil(saved.folderID); XCTAssertNotNil(saved.archivedAt)
        XCTAssertEqual(saved.title, "New title"); XCTAssertEqual(saved.messages, original.messages)
        try await store.setArchived(conversation.id, archived: false)
        let restored = try await store.searchMessages("Distinctive")
        XCTAssertEqual(restored.count, 1)
    }
    func testDeletionRemovesHistorySearchArtifactsDraftsAndChatOnlyMemory() async throws {
        let store = try makeTestStore()
        var conversation = Conversation(title: "Remove me")
        conversation.messages = [Message(role: .user, text: "uniquedeletionmarker")]
        try await store.save(conversation)
        let artifact = ArtifactRecord(conversationID: conversation.id, filename: "result.txt", content: "generated")
        try await store.saveArtifact(artifact)
        try await store.saveArtifactDraft(id: artifact.id, text: "draft")
        let global = SavedMemory(title: "Keep", text: "Global preference")
        try await store.saveMemory(global)
        try await store.saveMemory(SavedMemory(title: "Remove", text: "Chat preference", conversationID: conversation.id))
        let exported = try await store.exportArtifact(artifact)
        try await store.removeConversation(conversation.id)
        let history = try await store.searchMessages("uniquedeletionmarker")
        let generated = try await store.artifacts(), draft = try await store.artifactDraft(id: artifact.id)
        XCTAssertTrue(history.isEmpty); XCTAssertTrue(generated.isEmpty); XCTAssertNil(draft)
        XCTAssertFalse(FileManager.default.fileExists(atPath: exported.path))
        let memories = try await store.memories()
        XCTAssertEqual(memories.map(\.id), [global.id])
        do { _ = try await store.loadConversation(conversation.id); XCTFail("Deleted chat remains accessible") } catch { }
    }
    func testConnectedWorkspaceSearchExcludesWholeProtectedChatsAndTheirTitles() async throws {
        let store = try makeTestStore()
        for mode in 0..<4 {
            var conversation = Conversation(title: "marker title \(mode)")
            conversation.networkDisabled = mode == 1
            conversation.messages = [Message(role: .user, text: "marker ordinary query"),
                Message(role: .assistant, text: "marker protected reply", containsHealthData: mode == 2, containsLocalOnlyContext: mode == 3)]
            try await store.save(conversation)
        }
        let remote = try await store.searchMessages("marker", excludingProtectedConversations: true)
        XCTAssertEqual(Set(remote.map(\.title)), ["marker title 0"])
        let local = try await store.searchMessages("marker")
        XCTAssertEqual(Set(local.map(\.title)).count, 4)
    }
    func testSharedHistoryReadChecksScopeAndProtectedConversation() async throws {
        let store = try makeTestStore(), folder = ChatFolder(name: "Allowed")
        try await store.saveFolder(folder)
        var conversation = Conversation()
        conversation.folderID = folder.id
        conversation.messages = [Message(role: .user, text: "saved source")]
        try await store.save(conversation)
        let message = try await store.sharedHistoryMessage(conversation.messages[0].id, conversationID: conversation.id, folderID: folder.id, remote: true)
        XCTAssertEqual(message.text, "saved source")
        do { _ = try await store.sharedHistoryMessage(message.id, conversationID: conversation.id, folderID: UUID(), remote: false); XCTFail("Wrong folder accepted") } catch { }
        conversation.networkDisabled = true; try await store.save(conversation)
        do { _ = try await store.sharedHistoryMessage(message.id, conversationID: conversation.id, folderID: nil, remote: true); XCTFail("Private chat accepted") } catch { }
    }
}
