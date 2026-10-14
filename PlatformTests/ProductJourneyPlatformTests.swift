import AssistantCore
import XCTest
@preconcurrency import Speech
@testable import PersonalAssistant

@MainActor
final class ProductJourneyPlatformTests: XCTestCase {
    func testSpeechAuthorizationCompletionAcceptsAnOffMainCallback() async {
        let result = await withCheckedContinuation { continuation in
            let callback = SpeechCallbackBridge.authorization(continuation)
            DispatchQueue.global(qos: .userInitiated).async { callback(.authorized) }
        }
        XCTAssertEqual(result, .authorized)
    }
    func testSpeechRecognitionCompletionCopiesValuesBeforeReturningToUI() async {
        let update: SpeechCallbackBridge.Update = await withCheckedContinuation { continuation in
            let callback = SpeechCallbackBridge.recognition { continuation.resume(returning: $0) }
            DispatchQueue.global(qos: .userInitiated).async { callback(nil, NSError(domain: "SyntheticSpeech", code: 1)) }
        }
        XCTAssertEqual(update, .init(text: nil, isFinal: false, failed: true))
    }
    func testPreferenceCommitAndFailedWriteKeepPublishedAndPersistedValuesConsistent() async throws {
        let model = AppModel(); try await model.waitUntilReady()
        let original = model.settings
        defer { model.failPreferenceWritesForTest = false; try? model.saveSettings(original) }
        try model.updatePreference(\.allowCellularDownloads, to: !original.allowCellularDownloads)
        XCTAssertEqual(model.settings.allowCellularDownloads, !original.allowCellularDownloads)
        let persisted = AppModel(); try await persisted.waitUntilReady()
        XCTAssertEqual(persisted.settings.allowCellularDownloads, !original.allowCellularDownloads)
        model.failPreferenceWritesForTest = true
        XCTAssertThrowsError(try model.updatePreference(\.allowCellularDownloads, to: original.allowCellularDownloads))
        XCTAssertEqual(model.settings.allowCellularDownloads, !original.allowCellularDownloads)
        let reopened = AppModel(); try await reopened.waitUntilReady()
        XCTAssertEqual(reopened.settings.allowCellularDownloads, !original.allowCellularDownloads)
    }
    func testContextProposalPreservesDraftAndRejectsDelayedOwnerChange() async throws {
        let model = AppModel(); try await model.waitUntilReady()
        model.conversation = Conversation(); try await model.store!.save(model.conversation)
        let artifact = ArtifactRecord(conversationID: model.conversation.id, filename: "test.md", content: "Selected source")
        try await model.store!.saveArtifact(artifact)
        let ref = ContextReference(kind: .artifact, sourceID: artifact.id.uuidString, title: artifact.filename, conversationID: model.conversation.id, revision: 1)
        model.draft = "My unsent text"
        await model.offerContextualDraft(reference: ref, prompt: "Explain the source")
        XCTAssertNotNil(model.pendingContextualDraft); XCTAssertTrue(model.draftContextReferences.isEmpty)
        let proposal = model.pendingContextualDraft!
        model.acceptContextualDraft(proposal)
        XCTAssertEqual(model.draft, "My unsent text"); XCTAssertEqual(model.draftContextReferences.count, 1); XCTAssertFalse(model.isRunning)
        model.newConversation(); model.draft = "Another draft"
        model.acceptContextualDraft(proposal)
        XCTAssertEqual(model.draft, "Another draft"); XCTAssertTrue(model.draftContextReferences.isEmpty); XCTAssertFalse(model.isRunning)
    }
    func testArtifactEditorRestoresConflictedDraftAndDiscardKeepsNewerSavedText() async throws {
        let store = try LocalStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let chat = Conversation(); try await store.save(chat)
        let original = ArtifactRecord(conversationID: chat.id, filename: "test.md", content: "Original")
        try await store.saveArtifact(original)
        let editor = ArtifactEditor(artifact: original); await editor.load(store); editor.beginEditing(); editor.text = "My draft"; editor.changed(); await editor.flush()
        _ = try await store.reviseArtifact(id: original.id, expectedRevision: 1, content: "Independent saved edit")
        let saved = await editor.save(); XCTAssertNil(saved); XCTAssertTrue(editor.needsComparison); XCTAssertEqual(editor.text, "My draft")
        let reopened = ArtifactEditor(artifact: original); await reopened.load(store)
        XCTAssertTrue(reopened.editing); XCTAssertTrue(reopened.needsComparison); XCTAssertEqual(reopened.text, "My draft")
        await reopened.discard()
        XCTAssertFalse(reopened.hasDraft); XCTAssertEqual(reopened.text, "Independent saved edit")
        let stored = try await store.artifactRecord(original.id); XCTAssertEqual(stored.revision, 2)
    }
    func testAttachmentBatchIsAtomicWhenASelectedFileIsUnavailable() async throws {
        let model = AppModel(); try await model.waitUntilReady(); model.conversation = Conversation()
        let file = WorkspaceFile(filename: "valid.txt", mediaType: "text/plain", byteCount: 2, text: "OK")
        try await model.store!.saveWorkspaceFile(file, data: Data("OK".utf8)); model.attachedFileIDs = []
        do { try await model.attachSelectedFiles([file.id, UUID()], to: model.conversation.id); XCTFail("Missing file must fail the whole selection") } catch { }
        XCTAssertTrue(model.attachedFileIDs.isEmpty)
        try await model.attachSelectedFiles([file.id, file.id], to: model.conversation.id)
        XCTAssertEqual(model.attachedFileIDs, [file.id])
    }
    func testContextRoutingWaitsForRealDismissalAndRetainsTheSelectedIdentity() {
        let router = ChatNavigation(), owner = UUID()
        let proposal = ContextualDraftProposal(reference: ContextReference(kind: .file, sourceID: UUID().uuidString, title: "Example", conversationID: owner), prompt: "Explain")
        router.compose(proposal, afterDismissal: true)
        XCTAssertTrue(router.waitsForDismissal); XCTAssertEqual(router.pendingContext, proposal)
        router.presentationDidDismiss(); XCTAssertFalse(router.waitsForDismissal)
        XCTAssertEqual(router.takeContext(), proposal); XCTAssertNil(router.takeContext())
    }
}
