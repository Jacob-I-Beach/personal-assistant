import XCTest
@testable import AssistantCore

final class ProductNavigationTests: XCTestCase, @unchecked Sendable {
    func testLibrarySearchIncludesCurrentDocumentContentAndHasAnExplicitEmptyResult() async throws {
        let store = try makeTestStore(), chat = Conversation(); try await store.save(chat)
        let old = ArtifactRecord(conversationID: chat.id, filename: "draft.md", content: "Old needle")
        let current = ArtifactRecord(conversationID: chat.id, filename: "final.md", content: "Current lighthouse", previousRevisionID: old.id)
        try await store.saveArtifact(old); try await store.saveArtifact(current)
        let file = WorkspaceFile(filename: "rows.csv", mediaType: "text/csv", byteCount: 10, text: "lighthouse")
        try await store.saveWorkspaceFile(file, data: Data("lighthouse".utf8))
        let result = try await store.searchLibrary("LIGHTHOUSE")
        XCTAssertEqual(result.artifactIDs, [current.id]); XCTAssertEqual(result.fileIDs, [file.id])
        let missing = try await store.searchLibrary("absent phrase")
        XCTAssertTrue(missing.fileIDs.isEmpty); XCTAssertTrue(missing.artifactIDs.isEmpty)
        let oldResult = try await store.searchLibrary("Old needle"); XCTAssertTrue(oldResult.artifactIDs.isEmpty)
    }
    func testServerHistoryKeepsSelectedContextIdentityWithoutCopyingPrivateSnapshots() throws {
        var chat = Conversation()
        let ref = ContextReference(kind: .surface, sourceID: UUID().uuidString, title: "Source title", conversationID: chat.id, revision: 4, snapshot: "Do not duplicate this snapshot")
        let privateRef = ContextReference(kind: .inbox, sourceID: UUID().uuidString, title: "Private", conversationID: chat.id, localOnly: true, snapshot: "Private canary")
        var message = Message(role: .user, text: "Explain my selection"); message.contextReferences = [ref, privateRef]; chat.messages = [message]
        let snapshot = ServerContextSnapshot.make(conversation: chat, memories: [])
        XCTAssertEqual(snapshot["history"]?.arrayValue?.first?["text"], .string("Explain my selection"))
        XCTAssertEqual(snapshot["history"]?.arrayValue?.first?["selected_context"]?.arrayValue?.count, 1)
        XCTAssertFalse(try snapshot.jsonString().contains("Private canary")); XCTAssertFalse(try snapshot.jsonString().contains("Do not duplicate"))
    }
    func testOldSearchHitUsesAnExactBoundedWindowAndDetectsChangedText() async throws {
        let store = try makeTestStore(); var chat = Conversation()
        chat.messages = (0..<300).map { Message(role: .assistant, text: $0 == 12 ? "Distinctive navigation canary" : "Other answer \($0)") }
        try await store.save(chat)
        let match = try await store.searchMessages("navigation canary").first!
        let saved = try await store.loadConversation(chat.id)
        let landing = try HistoryLanding(match: match, conversation: saved)
        XCTAssertEqual(landing.messageID, chat.messages[12].id)
        XCTAssertEqual(landing.anchorID, chat.messages[12].id)
        XCTAssertLessThanOrEqual(landing.upperBound - landing.lowerBound, 100)
        XCTAssertTrue((landing.lowerBound..<landing.upperBound).contains(12)); XCTAssertLessThan(landing.upperBound, 300)
        var changed = saved; changed.messages[12].text = "Changed answer"
        XCTAssertThrowsError(try HistoryLanding(match: match, conversation: changed))
        changed.messages.remove(at: 12)
        XCTAssertThrowsError(try HistoryLanding(match: match, conversation: changed))
        XCTAssertThrowsError(try HistoryLanding(match: match, conversation: Conversation()))
    }
    func testLiteralCSVPreviewHandlesQuotedCellsAndBoundsWithoutExecutingFormulas() {
        let value = DelimitedPreview("name,note\r\nA,\"one,two\"\r\nB,\"line one\nline two\"\r\nC,\"say \"\"hello\"\"\"\r\nD,=1+1\r\n")
        XCTAssertEqual(value.rows, [["name", "note"], ["A", "one,two"], ["B", "line one\nline two"], ["C", "say \"hello\""], ["D", "=1+1"]])
        XCTAssertFalse(value.truncated)
        let bounded = DelimitedPreview("a,b,c\n1,2,3\n4,5,6", maximumRows: 2, maximumColumns: 2)
        XCTAssertEqual(bounded.rows, [["a", "b"], ["1", "2"]]); XCTAssertTrue(bounded.truncated)
        XCTAssertEqual(DelimitedPreview("one\ttwo", delimiter: "\t").rows, [["one", "two"]])
    }
    func testComputerCatalogCannotClaimAvailabilityFromAnAccountOrUnknownState() throws {
        let unavailable: JSONValue = .object(["profile_id": .string("owner"), "models": .array([]), "catalog": .object(["state": .string("unavailable"), "error": .string("HTTP 520")])])
        let result = try ModelCatalogState.computerObservation(unavailable, profileID: "owner", owner: "computer")
        XCTAssertEqual(result.phase, .unavailable); XCTAssertTrue(result.detail.contains("520"))
        XCTAssertThrowsError(try ModelCatalogState.computerObservation(unavailable, profileID: "other", owner: "computer"))
        let unknown: JSONValue = .object(["profile_id": .string("owner"), "models": .array([]), "catalog": .object(["state": .string("unknown")])])
        XCTAssertThrowsError(try ModelCatalogState.computerObservation(unknown, profileID: "owner", owner: "computer"))
    }
}
