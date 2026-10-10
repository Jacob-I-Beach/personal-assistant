import Foundation
import XCTest
@testable import AssistantCore

final class ConversationInteractionTests: XCTestCase, @unchecked Sendable {
    func testAttachmentOnlyInputPreservesEmptyUserTextAndTypedImage() async throws {
        let store = try makeTestStore(), capture = testCapture(), recorder = InteractionRequests()
        try await store.saveCapture(capture, jpeg: Data([1, 2, 3]))
        let conversation = Conversation()
        for try await _ in AssistantEngine(store: store).respond(conversation: conversation, text: "", captureIDs: [capture.id], backend: InteractionBackend(recorder: recorder)) { }
        let saved = try await store.loadConversation(conversation.id)
        XCTAssertEqual(saved.messages.first?.text, "")
        let recorded = await recorder.latest()
        let request = try XCTUnwrap(recorded)
        XCTAssertEqual(request.messages.first?.message.text, "")
        XCTAssertEqual(request.messages.first?.images.first?.captureID, capture.id)
        XCTAssertTrue(request.instructions.contains("App-provided attachment metadata"))
        XCTAssertTrue(request.instructions.contains(capture.id.uuidString))
        XCTAssertFalse(request.instructions.contains("Help me understand the attached material"))
    }
    func testAttachmentWithTextKeepsTextExactlyAsWritten() async throws {
        let store = try makeTestStore(), capture = testCapture(), recorder = InteractionRequests()
        try await store.saveCapture(capture, jpeg: Data([1]))
        let text = "  What is this?\nDo not rewrite my message.  "
        for try await _ in AssistantEngine(store: store).respond(conversation: Conversation(), text: text, captureIDs: [capture.id], backend: InteractionBackend(recorder: recorder)) { }
        let recorded = await recorder.latest()
        let request = try XCTUnwrap(recorded)
        XCTAssertEqual(request.messages.first?.message.text, text)
    }
    func testImageOnlyResponsesWireHasNoInventedOrEmptyTextPart() throws {
        let backend = try NetworkModelBackend(baseURL: URL(string: "https://api.openai.com/v1")!, model: "gpt-6.1-sol", wireProtocol: .responses)
        let input = ModelRequest(instructions: "App attachment metadata", messages: [.init(message: Message(role: .user, text: ""), images: [.init(captureID: UUID(), jpeg: Data([1,2,3]))])], tools: [])
        let body = try JSONDecoder().decode(JSONValue.self, from: backend.makeRequest(input).httpBody!)
        let content = try XCTUnwrap(body["input"]?.arrayValue?.first?["content"]?.arrayValue)
        XCTAssertEqual(content.count, 1); XCTAssertEqual(content[0]["type"], .string("input_image"))
    }
    func testSelectedImagePointsAreMetadataAndRepeatedImagesAreNotDuplicated() async throws {
        let store = try makeTestStore(), capture = testCapture(), recorder = InteractionRequests()
        try await store.saveCapture(capture, jpeg: Data([1]))
        var conversation = Conversation()
        conversation.messages = [Message(role: .user, text: "Earlier image", captureIDs: [capture.id]), Message(role: .assistant, text: "Seen")]
        let selected = [capture.id.uuidString: [ImagePoint(x: 0.2, y: 0.7)]]
        for try await _ in AssistantEngine(store: store).respond(conversation: conversation, text: "", captureIDs: [capture.id], backend: InteractionBackend(recorder: recorder), imageSelections: selected) { }
        let recorded = await recorder.latest(), request = try XCTUnwrap(recorded)
        XCTAssertEqual(request.messages.flatMap(\.images).count, 1)
        XCTAssertEqual(request.messages.last?.message.text, "")
        XCTAssertEqual(request.messages.last?.message.imageSelections, selected)
        XCTAssertTrue(request.instructions.contains("user_selected_points"))
        XCTAssertTrue(request.instructions.contains("\"x\":0.2"))
    }
    func testSelectionCannotClaimAnUnattachedImage() async throws {
        let store = try makeTestStore(), recorder = InteractionRequests()
        do {
            for try await _ in AssistantEngine(store: store).respond(conversation: Conversation(), text: "Inspect", captureIDs: [], backend: InteractionBackend(recorder: recorder), imageSelections: [UUID().uuidString: [.init(x: 0.5, y: 0.5)]]) { }
            XCTFail("A selection escaped attachment scope")
        } catch { XCTAssertTrue(error.localizedDescription.contains("attached images")) }
        let request = await recorder.latest(); XCTAssertNil(request)
    }
    func testEditExcludesFutureFromModelSearchAndLibraryRetrieval() async throws {
        let store = try makeTestStore(), recorder = InteractionRequests()
        var conversation = Conversation()
        let keep = Message(role: .user, text: "Keep this earlier context")
        let edited = Message(role: .user, text: "1+1")
        let call = ToolCall(id: "future-call", name: "create_artifact", arguments: .object([:]))
        var answer = Message(role: .assistant, text: "future-secret-sentinel"); answer.toolCalls = [call]
        answer.continuation = ProviderContinuation(providerID: "interaction-fixture", items: [.object(["secret": .string("future-secret-sentinel")])])
        conversation.messages = [keep, Message(role: .assistant, text: "Understood"), edited, answer]
        try await store.save(conversation)
        let artifact = ArtifactRecord(conversationID: conversation.id, filename: "answer.txt", content: "future-secret-sentinel", sourceCallID: call.id)
        try await store.saveArtifact(artifact)
        let file = WorkspaceFile(filename: "answer.pdf", mediaType: "application/pdf", byteCount: 3, text: "future-secret-sentinel", allowsWorkspaceSearch: true, allowsConnectedModels: true, conversationID: conversation.id)
        try await store.saveWorkspaceFile(file, data: Data([1, 2, 3]))
        let revised = try await store.prepareMessageEdit(in: conversation, messageID: edited.id)
        XCTAssertEqual(revised.messages.count, 2)
        let matches = try await store.searchMessages("future-secret-sentinel")
        XCTAssertTrue(matches.isEmpty)
        let visibleArtifacts = try await store.readableArtifacts(conversationID: conversation.id, workspace: true, remote: false)
        let visibleFiles = try await store.readableFiles(attached: [], workspace: true, remote: false, conversationID: conversation.id)
        XCTAssertTrue(visibleArtifacts.isEmpty); XCTAssertTrue(visibleFiles.isEmpty)
        let libraryArtifacts = try await store.artifacts(), libraryFiles = try await store.workspaceFiles()
        XCTAssertEqual(libraryArtifacts.count, 1); XCTAssertEqual(libraryFiles.count, 1)
        for try await _ in AssistantEngine(store: store).respond(conversation: revised, text: "1+2", captureIDs: [], backend: InteractionBackend(recorder: recorder)) { }
        let recorded = await recorder.latest()
        let request = try XCTUnwrap(recorded)
        XCTAssertEqual(request.messages.map(\.message.text), ["Keep this earlier context", "Understood", "1+2"])
        XCTAssertFalse(request.instructions.contains("future-secret-sentinel"))
        XCTAssertTrue(request.messages.allSatisfy { $0.message.continuation == nil })
    }
    func testStaleEditDoesNotRemoveNewerWork() async throws {
        let store = try makeTestStore()
        var original = Conversation(); original.messages = [Message(role: .user, text: "First")]
        try await store.save(original)
        var newer = original; newer.messages.append(Message(role: .assistant, text: "Newer work")); try await store.save(newer)
        do { _ = try await store.prepareMessageEdit(in: original, messageID: original.messages[0].id); XCTFail("Stale edit committed") }
        catch { XCTAssertTrue(error.localizedDescription.contains("changed")) }
        let saved = try await store.loadConversation(original.id)
        XCTAssertEqual(saved.messages.last?.text, "Newer work")
    }
    func testEditedRequestCannotLeakBackThroughAnOldChatTitle() async throws {
        let store = try makeTestStore()
        var conversation = Conversation(title: "The old secret request")
        conversation.titleWasGenerated = true
        let first = Message(role: .user, text: "Retain this earlier context"), edited = Message(role: .user, text: "Old secret request")
        conversation.messages = [first, Message(role: .assistant, text: "Understood"), edited]
        try await store.save(conversation)
        let revised = try await store.prepareMessageEdit(in: conversation, messageID: edited.id)
        XCTAssertTrue(revised.needsAutomaticTitle)
        let results = try await store.searchMessages("earlier", conversationID: conversation.id)
        XCTAssertEqual(results.first?.title, "Conversation")
        XCTAssertFalse(results.contains { $0.title.contains("secret") })
    }
    func testOldConversationDecodesWithoutEditMetadata() throws {
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        var value = try JSONDecoder().decode(JSONValue.self, from: encoder.encode(Conversation())).objectValue!
        value.removeValue(forKey: "excludedArtifactIDs"); value.removeValue(forKey: "excludedFileIDs")
        let decoded = try decoder.decode(Conversation.self, from: JSONValue.object(value).jsonString().data(using: .utf8)!)
        XCTAssertTrue(decoded.excludedArtifactIDs.isEmpty); XCTAssertTrue(decoded.excludedFileIDs.isEmpty)
    }
    func testDepthRotationAndCalibratedSeparation() throws {
        let grid = DepthGrid(width: 10, height: 10, meters: Array(repeating: 2, count: 100), confidence: Array(repeating: 2, count: 100))
        for rotation in [0, 90, 180, 270] {
            let capture = CaptureObservation(source: "Synthetic", imageWidth: 100, imageHeight: 100, imageRotationDegrees: rotation, depth: grid, cameraIntrinsics: [100,0,0,0,100,0,49.5,49.5,1], trackingState: "normal")
            let result = try DepthInspection.inspect(capture, points: [.init(x: 0.25, y: 0.25), .init(x: 0.75, y: 0.25)])
            XCTAssertEqual(try XCTUnwrap(result.separationMeters), 1, accuracy: 0.0001)
            XCTAssertEqual(result.readings[0].acceptedSamples, 9)
            XCTAssertEqual(result.readings[0].axialMeters, 2)
        }
    }
    func testDepthRejectsInvalidPointsAndUnreliableSamples() throws {
        let grid = DepthGrid(width: 5, height: 5, meters: Array(repeating: 2, count: 25), confidence: Array(repeating: 0, count: 25))
        let capture = CaptureObservation(source: "Synthetic", imageWidth: 100, imageHeight: 100, depth: grid, trackingState: "limited")
        XCTAssertThrowsError(try DepthInspection.inspect(capture, points: [.init(x: 1.01, y: 0.5)]))
        let result = try DepthInspection.inspect(capture, points: [.init(x: 0.5, y: 0.5)])
        XCTAssertNil(result.readings[0].axialMeters); XCTAssertNil(result.separationMeters)
        XCTAssertEqual(result.readings[0].excludedSamples, 9)
        XCTAssertFalse(result.warnings.isEmpty)
    }
    func testDepthRotationSelectsTheCorrectNativeCorner() throws {
        let values: [Float?] = (0..<8).flatMap { y in (0..<6).map { x in Optional(Float(x * 10 + y + 1)) } }
        for (rotation, expected) in [(0, 6.5), (90, 12.5), (180, 52.5), (270, 46.5)] {
            let capture = CaptureObservation(source: "Synthetic corners", imageWidth: 600, imageHeight: 800, imageRotationDegrees: rotation, depth: .init(width: 6, height: 8, meters: values))
            let inspection = try DepthInspection.inspect(capture, points: [.init(x: 0, y: 0)])
            XCTAssertEqual(inspection.readings[0].axialMeters, expected)
        }
    }
    func testDepthToolCannotReadAnotherConversationsCapture() async throws {
        let store = try makeTestStore(), capture = testCapture()
        try await store.saveCapture(capture, jpeg: Data([1]))
        let broker = CaptureToolBroker(store: store, allowedCaptureIDs: [])
        let result = await broker.execute(.init(id: "scope", name: "inspect_depth", arguments: .object(["capture_id": .string(capture.id.uuidString), "points_json": .string("[{\"x\":0.5,\"y\":0.5}]")])))
        XCTAssertFalse(result.succeeded)
    }
}
private actor InteractionRequests {
    var requests: [ModelRequest] = []
    func add(_ request: ModelRequest) { requests.append(request) }
    func latest() -> ModelRequest? { requests.last }
}
private struct InteractionBackend: ModelBackend {
    let recorder: InteractionRequests
    var id: String { "interaction-fixture" }
    var networkDestination: String? { nil }
    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        AsyncThrowingStream { output in
            let task = Task { await recorder.add(request); output.yield(.textDelta("Ready")); output.yield(.completed); output.finish() }
            output.onTermination = { _ in task.cancel() }
        }
    }
}
