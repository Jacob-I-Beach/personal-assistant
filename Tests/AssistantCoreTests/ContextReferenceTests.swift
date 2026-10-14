import XCTest
@testable import AssistantCore

final class ContextReferenceTests: XCTestCase, @unchecked Sendable {
    func testContextProposalKeepsExistingTextAndDistinguishesSameTitleSources() throws {
        let chat = UUID(), first = ContextReference(kind: .surface, sourceID: UUID().uuidString, title: "Same title", conversationID: chat, revision: 1)
        let second = ContextReference(kind: .surface, sourceID: UUID().uuidString, title: "Same title", conversationID: chat, revision: 3)
        let proposal = ContextualDraftProposal(reference: second, prompt: "Explain these changes")
        XCTAssertEqual(proposal.textPreservingExistingDraft("My next question"), "My next question")
        XCTAssertEqual(proposal.textPreservingExistingDraft(""), "Explain these changes")
        let result = try proposal.referencesAddingTo([first], conversationID: chat)
        XCTAssertEqual(result.map(\.sourceID), [first.sourceID, second.sourceID])
        XCTAssertEqual(try proposal.referencesAddingTo(result, conversationID: chat).count, 2)
        XCTAssertThrowsError(try proposal.referencesAddingTo([], conversationID: UUID()))
    }
    func testExactSelectedSourceReachesProductionRequestWithoutChangingStoredUserText() async throws {
        let store = try makeTestStore(), fixture = try await surfaceFixture(store), recorder = ContextRequestRecorder()
        let ref = ContextReference(kind: .surface, sourceID: fixture.surface.id.uuidString, title: fixture.surface.title, conversationID: fixture.chat.id, revision: 1)
        for try await _ in AssistantEngine(store: store).respond(conversation: fixture.chat, text: "Explain this", captureIDs: [], backend: ContextReferenceBackend(recorder: recorder), contextReferences: [ref]) { }
        let request = await recorder.request, stored = try await store.loadConversation(fixture.chat.id)
        let user = stored.messages.last(where: \.isRequest)!
        XCTAssertEqual(user.text, "Explain this"); XCTAssertEqual(user.contextReferences, [ref])
        XCTAssertTrue(request?.messages.last(where: { $0.message.isRequest })?.message.text.contains(fixture.surface.id.uuidString) == true)
        XCTAssertTrue(request?.messages.last(where: { $0.message.isRequest })?.message.text.contains("revision_at_selection") == true)
    }
    func testStaleOrProtectedContextIsRejectedBeforeProviderDispatch() async throws {
        for protected in [false, true] {
            let store = try makeTestStore(), fixture = try await surfaceFixture(store, localOnly: protected), recorder = ContextRequestRecorder()
            var chat = fixture.chat; chat.allowedNetworkDestinations.insert("https://fixture.invalid")
            try await store.save(chat)
            let ref = ContextReference(kind: .surface, sourceID: fixture.surface.id.uuidString, title: fixture.surface.title, conversationID: chat.id, revision: 1, localOnly: false)
            if !protected { _ = try await store.interactWithSurface(id: fixture.surface.id, conversationID: chat.id, expectedRevision: 1, selected: ["one"], inputs: [:]) }
            do {
                for try await _ in AssistantEngine(store: store).respond(conversation: chat, text: "Read selected context", captureIDs: [], backend: ContextReferenceBackend(recorder: recorder, networkDestination: "https://fixture.invalid"), contextReferences: [ref]) { }
                XCTFail("Invalid context was sent")
            } catch { }
            let count = await recorder.calls; XCTAssertEqual(count, 0)
        }
    }
    func testForeignHealthFileAndUnsharedCalendarReferenceDoNotGrantAccess() async throws {
        let store = try makeTestStore(), owner = Conversation(); try await store.save(owner)
        var other = Conversation(); other.allowedNetworkDestinations.insert("https://fixture.invalid"); try await store.save(other)
        let file = WorkspaceFile(filename: "synthetic-health.txt", mediaType: "text/plain", byteCount: 6, text: "canary", conversationID: owner.id, containsHealthData: true)
        try await store.saveWorkspaceFile(file, data: Data("canary".utf8))
        let foreign = ContextReference(kind: .file, sourceID: file.id.uuidString, title: "Selected file", conversationID: other.id)
        do { _ = try await store.validateContextReferences([foreign], conversationID: other.id, remote: false); XCTFail("Foreign Health file was allowed") } catch { }
        let recorder = ContextRequestRecorder(), calendar = ContextReference(kind: .calendar, sourceID: "synthetic-event", title: "Event", conversationID: other.id, snapshot: "Private event")
        do { for try await _ in AssistantEngine(store: store).respond(conversation: other, text: "Prepare", captureIDs: [], backend: ContextReferenceBackend(recorder: recorder, networkDestination: "https://fixture.invalid"), contextReferences: [calendar]) { }; XCTFail("Missing planning permission") } catch { }
        let count = await recorder.calls; XCTAssertEqual(count, 0)
    }
    private func surfaceFixture(_ store: LocalStore, localOnly: Bool = false) async throws -> (chat: Conversation, surface: WorkSurface) {
        var chat = Conversation(), create = Message(role: .assistant, text: "Created a view")
        create.toolCalls = [.init(id: "surface", name: "present_surface", arguments: .object([:]))]; chat.messages = [create]
        try await store.save(chat)
        let surface = try WorkSurface(conversationID: chat.id, sourceCallID: "surface", spec: .object(["kind": .string("checklist"), "title": .string("Same title"), "data": .array([.object(["id": .string("one"), "label": .string("Example"), "checked": .bool(false)])])]), localOnly: localOnly, health: false)
        try await store.saveSurface(surface); return (chat, surface)
    }
}
private actor ContextRequestRecorder {
    var request: ModelRequest?
    var calls = 0
    func record(_ value: ModelRequest) { request = value; calls += 1 }
}
private struct ContextReferenceBackend: ModelBackend {
    let recorder: ContextRequestRecorder
    let networkDestination: String?
    let id = "context-reference-fixture"
    init(recorder: ContextRequestRecorder, networkDestination: String? = nil) { self.recorder = recorder; self.networkDestination = networkDestination }
    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        AsyncThrowingStream { output in Task { await recorder.record(request); output.yield(.textDelta("Synthetic response")); output.yield(.completed); output.finish() } }
    }
}
