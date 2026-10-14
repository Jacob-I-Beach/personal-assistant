import XCTest
@testable import AssistantCore

final class ArtifactDraftTests: XCTestCase, @unchecked Sendable {
    func testRestoredDraftKeepsItsBaseAndCannotOverwriteANewerRevision() async throws {
        let store = try makeTestStore(), chat = Conversation(); try await store.save(chat)
        let original = ArtifactRecord(conversationID: chat.id, filename: "report.md", content: "Saved one")
        try await store.saveArtifact(original)
        try await store.saveArtifactDraft(id: original.id, text: "My unsaved edit", baseRevision: 1)
        _ = try await store.reviseArtifact(id: original.id, expectedRevision: 1, content: "Independent revision two")
        let reopened = try LocalStore(root: store.root), draft = try await reopened.artifactDraftRecord(id: original.id)
        XCTAssertEqual(draft?.baseRevision, 1); XCTAssertEqual(draft?.text, "My unsaved edit")
        do { _ = try await reopened.commitArtifactDraft(id: original.id, expectedRevision: draft?.baseRevision, text: draft!.text); XCTFail("A stale draft overwrote newer work") } catch { }
        let current = try await reopened.artifacts(conversationID: chat.id).first!
        XCTAssertEqual(current.revision, 2); XCTAssertEqual(current.content, "Independent revision two")
        let stillSaved = try await reopened.artifactDraftRecord(id: original.id); XCTAssertEqual(stillSaved, draft)
        // Rebase is a distinct explicit choice, preserving the independent revision in history.
        try await reopened.saveArtifactDraft(id: original.id, text: draft!.text, baseRevision: 2)
        let result = try await reopened.commitArtifactDraft(id: original.id, expectedRevision: 2, text: draft!.text)
        XCTAssertEqual(result.revision, 3)
        let removed = try await reopened.artifactDraftRecord(id: original.id), history = try await reopened.artifactHistory(original.id)
        XCTAssertNil(removed); XCTAssertEqual(history.map(\.content), ["Independent revision two", "Saved one"])
    }
    func testFailedRevisionCommitDoesNotDeleteTheDraft() async throws {
        let store = try makeTestStore(), chat = Conversation(); try await store.save(chat)
        let original = ArtifactRecord(conversationID: chat.id, filename: "report.txt", content: "Saved")
        try await store.saveArtifact(original); try await store.saveArtifactDraft(id: original.id, text: "Draft", baseRevision: 1)
        try await store.draftTestSQL("CREATE TEMP TRIGGER reject_revision BEFORE UPDATE ON artifacts BEGIN SELECT RAISE(FAIL,'synthetic failure'); END")
        do { _ = try await store.commitArtifactDraft(id: original.id, expectedRevision: 1, text: "Draft"); XCTFail("Injected failure") } catch { }
        let draft = try await store.artifactDraftRecord(id: original.id), current = try await store.artifacts().first!
        XCTAssertEqual(draft?.text, "Draft"); XCTAssertEqual(current.content, "Saved"); XCTAssertEqual(current.revision, 1)
        let history = try await store.artifactHistory(original.id); XCTAssertTrue(history.isEmpty)
    }
    func testDiscardLeavesTheCommittedDocumentAndDeletionRemovesDraftMetadata() async throws {
        let store = try makeTestStore(), chat = Conversation(); try await store.save(chat)
        let original = ArtifactRecord(conversationID: chat.id, filename: "report.txt", content: "Saved")
        try await store.saveArtifact(original)
        let persisted = try await store.artifacts().first!
        try await store.saveArtifactDraft(id: original.id, text: "Draft", baseRevision: 1)
        try await store.saveArtifactDraft(id: original.id, text: nil)
        let current = try await store.artifacts().first!; XCTAssertEqual(current, persisted)
        try await store.saveArtifactDraft(id: original.id, text: "Draft", baseRevision: 1)
        try await store.removeConversation(chat.id)
        let count = try await store.draftTestCount(); XCTAssertEqual(count, 0)
        do { try await store.saveArtifactDraft(id: original.id, text: "Late autosave", baseRevision: 1); XCTFail("Deleted draft revived") } catch { }
    }
    func testLegacyDraftCannotSilentlyAdoptTheCurrentRevision() async throws {
        let store = try makeTestStore(), chat = Conversation(); try await store.save(chat)
        let original = ArtifactRecord(conversationID: chat.id, filename: "report.txt", content: "Saved")
        try await store.saveArtifact(original)
        try await store.insertLegacyDraft(id: original.id, text: #"{"text":"still literal draft content"}"#)
        let draft = try await store.artifactDraftRecord(id: original.id)
        XCTAssertNil(draft?.baseRevision); XCTAssertEqual(draft?.text, #"{"text":"still literal draft content"}"#)
        do { _ = try await store.commitArtifactDraft(id: original.id, expectedRevision: nil, text: draft!.text); XCTFail("Unknown base committed") } catch { }
    }
}
private extension LocalStore {
    func draftTestSQL(_ sql: String) throws { try database.execute(sql) }
    func insertLegacyDraft(id: UUID, text: String) throws { try database.execute("INSERT INTO metadata(key,value) VALUES(?,?)", [.text("artifact-draft:" + id.uuidString), .text(text)]) }
    func draftTestCount() throws -> Int { Int(try database.execute("SELECT COUNT(*) FROM metadata WHERE key LIKE 'artifact-draft%'").first![0].number!) }
}
