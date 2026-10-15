import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import AssistantCore

final class ProductContractTests: XCTestCase, @unchecked Sendable {
    func testPresentationWaitsForDismissalAndNeverReplacesReview() {
        var state = PresentationState(); let review = AppPresentation.review(UUID())
        state.request(.library); XCTAssertEqual(state.active, .library)
        state.request(.projects); XCTAssertNil(state.active); XCTAssertEqual(state.pending, .projects)
        state.request(review); XCTAssertEqual(state.pending, review)
        state.request(.settings); XCTAssertEqual(state.pending, review)
        XCTAssertEqual(state.didDismiss(), .library); XCTAssertEqual(state.active, review)
        state.request(.models); XCTAssertEqual(state.active, review); XCTAssertEqual(state.pending, .models)
        state.cancel(review); XCTAssertNil(state.active)
        XCTAssertEqual(state.didDismiss(), review); XCTAssertEqual(state.active, .models)
        state.beginDismissal(); _ = state.didDismiss(); XCTAssertNil(state.active)
        let owner = ExecutionOwner(conversationID: UUID(), turnID: UUID())
        XCTAssertTrue(owner.matches(conversationID: owner.conversationID, turnID: owner.turnID))
        XCTAssertFalse(owner.matches(conversationID: UUID(), turnID: owner.turnID)); XCTAssertFalse(owner.matches(conversationID: owner.conversationID, turnID: UUID()))
    }
    func testSameProtocolNormalizationFixturesAsComputer() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/AssistantCore/Resources/ProtocolParity.json")
        let fixture = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: file))
        for row in fixture["normalization"]!.arrayValue! {
            let name = row["name"]!.stringValue!
            if row["error"] == .bool(true) { XCTAssertThrowsError(try ToolArguments.normalize(row["input"]!, schema: row["schema"]!), name) }
            else { XCTAssertEqual(try ToolArguments.normalize(row["input"]!, schema: row["schema"]!), row["expected"], name) }
        }
    }
    func testMemoryCanariesSelectParaphraseAndExcludeIrrelevantExpiredAndPrivate() {
        let chat = UUID()
        var food = SavedMemory(title: "Diet", text: "Vegetarian; avoid meat", allowsConnectedModels: true); food.kind = .preference
        let oldTopic = SavedMemory(title: "Astronomy project", text: "Measure orbit eccentricity", allowsConnectedModels: true)
        var expired = SavedMemory(title: "Food", text: "EXPIRED_CANARY", allowsConnectedModels: true); expired.status = .expired
        let privateNote = SavedMemory(title: "Food", text: "PRIVATE_CANARY")
        var superseded = food; superseded.id = UUID(); superseded.text = "SUPERSEDED_CANARY"; superseded.status = .superseded
        let text = MemoryContext.instructions([oldTopic, expired, privateNote, superseded, food], query: "Suggest a meal", conversationID: chat, remote: true)
        XCTAssertTrue(text.contains("Vegetarian")); XCTAssertFalse(text.contains("eccentricity")); XCTAssertFalse(text.contains("CANARY"))
        XCTAssertGreaterThan(RetrievalTerms.score("Vehicle service", query: RetrievalTerms.terms("car maintenance")), 0)
    }
    func testInboxMoveDeleteRestoreKeepsIdentityAndDoesNotStartWork() async throws {
        let store = try makeTestStore(); var chat = Conversation(); chat.networkDisabled = true; try await store.save(chat)
        let entry = InboxEntry(text: "Keep this idea", conversationID: nil, handling: .saveOnly)
        try await store.saveInboxEntry(entry); try await store.moveInboxEntry(entry.id, to: chat.id)
        let moved = try await store.inboxEntries(); XCTAssertEqual(moved.first?.id, entry.id); XCTAssertTrue(moved.first?.containsLocalOnlyContext == true)
        try await store.removeInboxEntry(entry.id)
        let active = try await store.inboxEntries(); XCTAssertTrue(active.isEmpty)
        let deleted = try await store.deletedInboxEntries(); XCTAssertEqual(deleted.first?.id, entry.id)
        try await store.restoreInboxEntry(entry.id)
        let restored = try await store.inboxEntries(); XCTAssertEqual(restored.first?.conversationID, chat.id)
        let work = try await store.unfinishedWork(); XCTAssertTrue(work.isEmpty)
    }
    func testModelCleanupRejectsRootTraversalAndPreservesUserData() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let package = root.appendingPathComponent("models/packages/fixture"), chat = root.appendingPathComponent("data/chat.json")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: chat.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("weights".utf8).write(to: package.appendingPathComponent("weights.bin")); try Data("keep".utf8).write(to: chat)
        let models = root.appendingPathComponent("models")
        XCTAssertThrowsError(try OwnedModelFiles.remove([root], root: models)); XCTAssertThrowsError(try OwnedModelFiles.remove([chat], root: models)); XCTAssertThrowsError(try OwnedModelFiles.remove([models.appendingPathComponent("packages")], root: models))
        XCTAssertEqual(try OwnedModelFiles.remove([package], root: models), 7)
        XCTAssertTrue(FileManager.default.fileExists(atPath: chat.path))
    }
    func testExactSurfaceInputHonorsStepAndUnknownWritesDoNotOfferRetry() {
        let input: JSONValue = .object(["min": .number(-2), "max": .number(3), "step": .number(0.2)])
        XCTAssertTrue(SurfaceInput.accepts(-1.8, specification: input)); XCTAssertFalse(SurfaceInput.accepts(-1.7, specification: input)); XCTAssertFalse(SurfaceInput.accepts(.nan, specification: input))
        let unknown = LocalRecovery(conversationID: UUID(), category: .unknownWriteOutcome, title: "Inspect result", detail: "Delivery was not confirmed", retained: "Receipt")
        XCTAssertFalse(unknown.canRetry)
    }
    func testSlowStreamConsumerFailsExplicitlyInsteadOfDroppingBytesSilently() async throws {
        guard let base = ProcessInfo.processInfo.environment["ASSISTANT_FIXTURE_BASE_URL"] else { throw XCTSkip("Use the integration fixture") }
        var request = URLRequest(url: URL(string: base + "/flood/responses")!); request.httpMethod = "POST"; request.httpBody = Data("{}".utf8)
        var iterator = URLSessionStreamingTransport().stream(request).makeAsyncIterator()
        _ = try await iterator.next()
        try await Task.sleep(for: .milliseconds(500))
        do { while let _ = try await iterator.next() {} ; XCTFail("A slow consumer silently accepted an unbounded stream") }
        catch { XCTAssertTrue(error.localizedDescription.contains("faster") || error is URLError) }
    }
    func testLargeHistoryCheckpointAndIndexedSearchBenchmark() async throws {
        let store = try makeTestStore(); var chat = Conversation(title: "Synthetic scale fixture")
        chat.messages = (0..<5000).map { Message(role: .assistant, text: "Synthetic saved message \($0) " + String(repeating: "context ", count: 30)) }
        try await store.save(chat)
        var cold: [Double] = []
        for index in 0..<6 {
            let independent = try LocalStore(root: store.root)
            chat.messages[4999].text += " baseline\(index)"
            let start = Date(); try await independent.save(chat); cold.append(Date().timeIntervalSince(start) * 1000)
        }
        var times: [Double] = []
        for index in 0..<12 {
            chat.messages[4999].text += " chunk\(index)"
            let start = Date(); try await store.save(chat); times.append(Date().timeIntervalSince(start) * 1000)
        }
        for index in 0..<1000 { try await store.saveArtifact(ArtifactRecord(conversationID: chat.id, filename: "fixture-\(index).md", content: index == 444 ? "Distinctive observatory" : "Unrelated fixture \(index)")) }
        _ = try await store.searchLibrary("observatory")
        var queries: [Double] = []
        for _ in 0..<12 { let start = Date(); let found = try await store.searchLibrary("observatory"); queries.append(Date().timeIntervalSince(start) * 1000); XCTAssertEqual(found.artifactIDs.count, 1) }
        let assembling = Date()
        let selection = try ContextPlanner.select(chat.messages, instructions: "Synthetic scale check", tools: [], limits: .init(maximumTextBytes: 80_000, maximumImages: 0))
        let assemblyMS = Date().timeIntervalSince(assembling) * 1000
        _ = selection
        times.sort(); queries.sort(); cold.sort()
        print("AUDIT120_BENCHMARK messages=5000 artifacts=1000 uncached_checkpoint_p50_ms=\(cold[3]) assembly_ms=\(assemblyMS) checkpoint_p50_ms=\(times[6]) checkpoint_p95_ms=\(times[11]) library_p50_ms=\(queries[6]) library_p95_ms=\(queries[11])")
        let loaded = try await store.loadConversation(chat.id); XCTAssertEqual(loaded.messages.count, 5000); XCTAssertEqual(loaded.messages.last?.text, chat.messages.last?.text)
    }
}
