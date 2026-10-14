import Foundation
import XCTest
@testable import AssistantCore

final class ModelPreparationTests: XCTestCase, @unchecked Sendable {
    func testPreparationEstablishesTheBudgetBeforeToolsAndContextAreAssembled() async throws {
        let store = try makeTestStore(), chat = Conversation(), script = ScriptedTurns([[.textDelta("Ready"), .completed]])
        let state = PreparationState(), backend = PreparingBackend(state: state, script: script)
        XCTAssertEqual(backend.contextLimits.maximumTextBytes, 4096)
        for try await _ in AssistantEngine(store: store).respond(conversation: chat, text: "Hello", captureIDs: [], backend: backend, appContext: .init()) { }
        let requests = await script.requests
        XCTAssertEqual(requests.count, 1); XCTAssertTrue(state.prepared)
        let saved = try await store.loadConversation(chat.id), work = try await store.workTurn(saved.messages[0].id)
        XCTAssertEqual(work?.configuration["context_text_bytes"], .number(32_768))
        XCTAssertEqual(saved.messages.last?.text, "Ready")
    }
    func testMemoryPreparationFailurePreservesRequestAndDoesNotBecomeAToolFitFailure() async throws {
        let store = try makeTestStore(), chat = Conversation(), script = ScriptedTurns([])
        let backend = PreparingBackend(state: PreparationState(), script: script, blocked: true)
        do {
            for try await _ in AssistantEngine(store: store).respond(conversation: chat, text: "Keep this request", captureIDs: [], backend: backend) { }
            XCTFail("Expected the resource failure")
        } catch { XCTAssertEqual(error.localizedDescription, "Synthetic memory headroom unavailable") }
        let requests = await script.requests
        XCTAssertTrue(requests.isEmpty)
        let saved = try await store.loadConversation(chat.id), work = try await store.workTurn(saved.messages[0].id)
        XCTAssertEqual(saved.messages.map(\.text), ["Keep this request"])
        XCTAssertNotEqual(work?.interruptionKind, "context_limit")
        XCTAssertNotEqual(work?.needsChangedRequest, true)
    }
}
private final class PreparationState: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var prepared: Bool { lock.withLock { value } }
    func finish() { lock.withLock { value = true } }
}
private struct PreparingBackend: ModelBackend {
    let id = "preparing-local-fixture", networkDestination: String? = nil
    let state: PreparationState
    let script: ScriptedTurns
    var blocked = false
    var contextLimits: ContextLimits { .init(maximumTextBytes: state.prepared ? 32_768 : 4096) }
    func prepareForResponse(containsImages: Bool) async throws {
        if blocked { throw AssistantError.provider("Synthetic memory headroom unavailable") }
        state.finish()
    }
    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> { ScriptedBackend(script: script).stream(request) }
}
