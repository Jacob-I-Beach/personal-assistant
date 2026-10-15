import XCTest
@testable import AssistantCore

final class AuditCompletionTests: XCTestCase, @unchecked Sendable {
    func testBranchPreservesPriorMessagesOutputsAndRestoresWithoutResuming() async throws {
        let store = try makeTestStore(); var chat = Conversation(title: "Original")
        chat.messages = [Message(role: .user, text: "Original request"), Message(role: .assistant, text: "Original answer")]
        chat.allowedNetworkDestinations = ["old-service"]
        try await store.save(chat)
        let artifact = ArtifactRecord(conversationID: chat.id, filename: "report.md", content: "Prior version")
        try await store.saveArtifact(artifact)
        let revised = try await store.prepareMessageEdit(in: chat, messageID: chat.messages[0].id)
        XCTAssertTrue(revised.messages.isEmpty)
        let branches = try await store.conversationRevisions(chat.id)
        XCTAssertEqual(branches.count, 1); XCTAssertEqual(try LocalStore.encode(branches[0].conversation.messages), try LocalStore.encode(chat.messages))
        XCTAssertEqual(branches[0].artifacts.first?.content, "Prior version")
        var edited = revised; edited.allowedNetworkDestinations = []; edited.networkDisabled = true
        edited.messages = [Message(role: .user, text: "Replacement request")]; try await store.save(edited)
        let expected = try await store.loadConversation(chat.id, preservingStreaming: true)
        let restored = try await store.restoreConversationRevision(branches[0].id, expected: expected)
        XCTAssertEqual(try LocalStore.encode(restored.messages), try LocalStore.encode(chat.messages)); XCTAssertTrue(restored.allowedNetworkDestinations.isEmpty); XCTAssertTrue(restored.networkDisabled)
        XCTAssertTrue(restored.excludedArtifactIDs.contains(artifact.id))
        let remaining = try await store.unfinishedWork(); XCTAssertTrue(remaining.isEmpty)
        let history = try await store.conversationRevisions(chat.id); XCTAssertEqual(history.count, 2)
        do { _ = try await store.restoreConversationRevision(branches[0].id, expected: expected); XCTFail("Accepted stale restore") } catch { }
        try await store.removeConversation(chat.id)
        let removed = try await store.conversationRevisions(chat.id); XCTAssertTrue(removed.isEmpty)
    }
    func testDirectProjectCreationPreservesScopeAndDoesNotOverwrite() async throws {
        let store = try makeTestStore(); var chat = Conversation(title: "Existing chat")
        let folder = ChatFolder(name: "Research"); try await store.saveFolder(folder)
        chat.folderID = folder.id; chat.networkDisabled = true; try await store.save(chat)
        let project = try await store.createProject(title: "Research goal", goal: "Find primary sources", conversationID: chat.id)
        XCTAssertEqual(project.id, folder.id); XCTAssertEqual(project.sourceConversationID, chat.id); XCTAssertTrue(project.containsLocalOnlyContext)
        do { _ = try await store.createProject(title: "Overwrite", conversationID: chat.id); XCTFail("Overwrote existing project") } catch { }
        let separate = try await store.createProject(title: "New work")
        let created = try await store.loadConversation(separate.sourceConversationID)
        XCTAssertTrue(created.messages.isEmpty); XCTAssertEqual(created.title, "New work")
    }
    func testIndexedSearchTracksRevisionsRemovalFiltersAndRebuild() async throws {
        let store = try makeTestStore(), chat = Conversation(); try await store.save(chat)
        let artifact = ArtifactRecord(conversationID: chat.id, filename: "report.md", content: "Initial lighthouse")
        try await store.saveArtifact(artifact)
        var filter = LibrarySearchFilter(); filter.conversationID = chat.id; filter.fileExtension = "md"
        let first = try await store.searchLibrary("lighth", filter: filter); XCTAssertEqual(first.artifactIDs, [artifact.id]); XCTAssertTrue(first.excerpts[artifact.id]?.contains("lighthouse") == true)
        _ = try await store.reviseArtifact(id: artifact.id, expectedRevision: 1, content: "Revised observatory")
        let old = try await store.searchLibrary("lighthouse"); XCTAssertTrue(old.artifactIDs.isEmpty)
        let current = try await store.searchLibrary("observatory", filter: filter); XCTAssertEqual(current.artifactIDs, [artifact.id])
        filter.fileExtension = "pdf"; let wrong = try await store.searchLibrary("observatory", filter: filter); XCTAssertTrue(wrong.artifactIDs.isEmpty)
        try await store.rebuildLibraryIndex()
        let rebuilt = try await store.searchLibrary("observatory"); XCTAssertEqual(rebuilt.artifactIDs, [artifact.id])
        try await store.removeConversation(chat.id)
        let removed = try await store.searchLibrary("observatory"); XCTAssertTrue(removed.artifactIDs.isEmpty)
    }
    func testArchiveRoundTripPreservesIdentityHistoryAndExcludesCredentialsAndExecution() async throws {
        let store = try makeTestStore(); var chat = Conversation(title: "Archive canary")
        chat.messages = [Message(role: .user, text: "Keep my notes"), Message(role: .assistant, text: "Saved answer")]
        chat.allowedNetworkDestinations = ["old-account"]
        try await store.save(chat)
        let artifact = ArtifactRecord(conversationID: chat.id, filename: "notes.md", content: "Revision one")
        try await store.saveArtifact(artifact); _ = try await store.reviseArtifact(id: artifact.id, expectedRevision: 1, content: "Revision two")
        let file = WorkspaceFile(filename: "rows.csv", mediaType: "text/csv", byteCount: 4, text: "a,b\n", allowsWorkspaceSearch: true, allowsConnectedModels: true, conversationID: chat.id)
        try await store.saveWorkspaceFile(file, data: Data("a,b\n".utf8))
        let project = try await store.createProject(title: "Archive project", conversationID: chat.id)
        let url = store.root.appendingPathComponent("test.paarchive")
        let inspection = try await store.exportPersonalArchive(to: url)
        XCTAssertEqual(inspection.manifest.conversations.map(\.id), [chat.id]); XCTAssertTrue(inspection.manifest.exclusions.contains("Account credentials and pairing keys"))
        let destination = try await PersonalArchive.stageRestore(url, in: store.root.appendingPathComponent("restores"))
        let restored = try LocalStore(root: destination)
        let restoredChat = try await restored.loadConversation(chat.id)
        XCTAssertEqual(try LocalStore.encode(restoredChat.messages), try LocalStore.encode(chat.messages)); XCTAssertTrue(restoredChat.allowedNetworkDestinations.isEmpty); XCTAssertTrue(restoredChat.requiresNetworkReview)
        let docs = try await restored.artifacts(); XCTAssertEqual(docs.first?.id, artifact.id); XCTAssertEqual(docs.first?.revision, 2)
        let history = try await restored.artifactHistory(artifact.id); XCTAssertEqual(history.first?.content, "Revision one")
        let original = try await restored.workspaceFile(file.id); XCTAssertFalse(original.allowsConnectedModels); XCTAssertFalse(original.allowsWorkspaceSearch)
        let projects = try await restored.projectWorkspaces(); XCTAssertEqual(projects.first?.id, project.id)
        let work = try await restored.unfinishedWork(); XCTAssertTrue(work.isEmpty)
        let originalPath = try await restored.workspaceFileURL(file.id); XCTAssertEqual(try Data(contentsOf: originalPath), Data("a,b\n".utf8))
        var damaged = try Data(contentsOf: url); damaged[damaged.count - 1] ^= 1
        let corrupt = store.root.appendingPathComponent("corrupt.paarchive"); try damaged.write(to: corrupt)
        XCTAssertThrowsError(try PersonalArchive.inspect(corrupt))
        let originalChats = try await store.conversationSummaries(); XCTAssertEqual(originalChats.count, 1)
    }
    func testDefaultArchiveDoesNotExportProtectedChatOrItsDerivedProject() async throws {
        let store = try makeTestStore(); var privateChat = Conversation(title: "Private canary")
        privateChat.networkDisabled = true; privateChat.messages = [Message(role: .user, text: "Private record")]
        try await store.save(privateChat); _ = try await store.createProject(title: "Private project", conversationID: privateChat.id)
        var health = Conversation(title: "Health canary"); var message = Message(role: .user, text: "Health record"); message.containsHealthData = true; health.messages = [message]; try await store.save(health)
        let report = try await store.exportPersonalArchive(to: store.root.appendingPathComponent("public.paarchive"))
        XCTAssertTrue(report.manifest.conversations.isEmpty); XCTAssertTrue(report.manifest.projects.isEmpty)
        let explicit = try await store.exportPersonalArchive(to: store.root.appendingPathComponent("private.paarchive"), includePrivate: true, includeHealth: false)
        XCTAssertEqual(explicit.manifest.conversations.map(\.id), [privateChat.id]); XCTAssertEqual(explicit.manifest.projects.count, 1)
    }
    func testArchiveRejectsDuplicateIdentitiesAndPathTraversalBeforeActivation() async throws {
        let store = try makeTestStore(); let chat = Conversation(title: "Preserved")
        try await store.save(chat)
        let file = WorkspaceFile(filename: "source.txt", mediaType: "text/plain", byteCount: 4, text: "safe", allowsConnectedModels: true)
        try await store.saveWorkspaceFile(file, data: Data("safe".utf8))
        let original = try await store.exportPersonalArchive(to: store.root.appendingPathComponent("good.paarchive"))
        var duplicate = original.manifest; duplicate.conversations += duplicate.conversations
        let dup = store.root.appendingPathComponent("duplicate.paarchive")
        try PersonalArchive.write(manifest: duplicate, to: dup) { _ in Data("safe".utf8) }
        XCTAssertThrowsError(try PersonalArchive.inspect(dup))
        var traversal = original.manifest; traversal.files[0].filename = "../escape.txt"
        let bad = store.root.appendingPathComponent("traversal.paarchive")
        try PersonalArchive.write(manifest: traversal, to: bad) { _ in Data("safe".utf8) }
        do { _ = try await PersonalArchive.stageRestore(bad, in: store.root.appendingPathComponent("restores")); XCTFail("Accepted a path outside the library") } catch { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.root.appendingPathComponent("escape.txt").path))
        let saved = try await store.loadConversation(chat.id); XCTAssertEqual(saved.title, "Preserved")
    }
    func testOutputPresentationRetainsDistinctIdentityAndOriginAcrossRevisions() throws {
        var chat = Conversation(); let user = Message(role: .user, text: "Create a report")
        let call = ToolCall(id: "source-create", name: "create_artifact", arguments: .object([:]))
        chat.messages = [user, Message(role: .assistant, text: "", toolCalls: [call])]
        var artifact = ArtifactRecord(conversationID: chat.id, filename: "report.md", content: "First", sourceCallID: call.id, containsLocalOnlyContext: true)
        let first = OutputPresentation(artifact, conversation: chat)
        artifact.revision = 2; artifact.content = "Second"
        let current = OutputPresentation(artifact, conversation: chat)
        XCTAssertEqual(first.id, current.id); XCTAssertEqual(current.revision, 2); XCTAssertEqual(current.originTurnID, user.id); XCTAssertTrue(current.localOnly)
        let sameName = WorkspaceFile(filename: "report.md", mediaType: "text/markdown", byteCount: 5, text: "Other")
        let input = OutputPresentation(sameName)
        XCTAssertNotEqual(input.id, current.id); XCTAssertTrue(input.isInput); XCTAssertTrue(input.restrictedDiscovery)
        XCTAssertEqual(current.preview, .textAvailable); XCTAssertEqual(input.preview, .originalNeedsCheck)
    }
    func testCheckpointCacheInvalidatesAfterEditAndExternalStoreMutation() async throws {
        let store = try makeTestStore(); var chat = Conversation(); chat.messages = (0..<1000).map { Message(role: .assistant, text: "Saved message \($0)") }
        try await store.save(chat)
        chat.messages.append(Message(role: .assistant, text: "Streaming")); try await store.save(chat)
        let other = try LocalStore(root: store.root)
        var different = chat; different.messages[10].text = "External write"; try await other.save(different)
        chat.messages[1000].text += " more"; try await store.save(chat)
        let loaded = try await store.loadConversation(chat.id); XCTAssertEqual(try LocalStore.encode(loaded.messages), try LocalStore.encode(chat.messages))
    }
}
