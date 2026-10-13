import XCTest
@testable import AssistantCore

final class RemoteContinuityTests: XCTestCase, @unchecked Sendable {
    func testObservationRetriesTransportLossButDoesNotLoopOnAccessOrTrustErrors() {
        XCTAssertTrue(CompanionObservationPolicy.shouldRetry(URLError(.networkConnectionLost)))
        XCTAssertTrue(CompanionObservationPolicy.shouldRetry(URLError(.notConnectedToInternet)))
        XCTAssertFalse(CompanionObservationPolicy.shouldRetry(URLError(.serverCertificateUntrusted)))
        XCTAssertFalse(CompanionObservationPolicy.shouldRetry(AssistantError.networkNotAuthorized))
        XCTAssertFalse(CompanionObservationPolicy.shouldRetry(CancellationError()))
    }
    func testDetachedObserverKeepsLiveMessageAndRejoinsTheSameSavedWork() async throws {
        let store = try makeTestStore(), engine = AssistantEngine(store: store)
        let chat = Conversation(), messageID = UUID()
        var sawLive = false
        do {
            for try await event in engine.respond(conversation: chat, text: "Keep working while I am away", captureIDs: [],
                backend: SavedComputerFixture(store: store, messageID: messageID, complete: false)) {
                if case .conversation(let value) = event, let reply = value.messages.last(where: { $0.role == .assistant }) {
                    XCTAssertEqual(reply.state, .streaming); sawLive = true
                }
            }
            XCTFail("The synthetic observer should detach")
        } catch is CancellationError { }
        XCTAssertTrue(sawLive)
        let detached = try await store.loadConversation(chat.id)
        XCTAssertEqual(detached.messages.last?.state, .streaming)
        let turn = try XCTUnwrap(detached.messages.first?.id)
        let work = try await store.workTurn(turn)
        XCTAssertEqual(work?.phase, .interrupted)
        XCTAssertEqual(work?.interruptionKind, "computer_detached")
        let unfinished = try await store.unfinishedWork()
        XCTAssertEqual(unfinished.map(\.id), [turn])
        let before = try await store.companionRun(turn)
        for try await _ in engine.resume(conversation: detached, turnID: turn,
            backend: SavedComputerFixture(store: store, messageID: messageID, complete: true)) { }
        let final = try await store.loadConversation(chat.id)
        XCTAssertEqual(final.messages.filter(\.isRequest).count, 1)
        XCTAssertEqual(final.messages.last?.id, messageID)
        XCTAssertEqual(final.messages.last?.state, .complete)
        XCTAssertEqual(final.messages.last?.text, "The saved result is ready.")
        let after = try await store.companionRun(turn)
        XCTAssertEqual(after?.jobID, before?.jobID)
        let completed = try await store.workTurn(turn)
        XCTAssertEqual(completed?.phase, .completed)
    }

    func testPhoneOwnedOrExplicitlyStoppedStreamsStillRecoverAsInterrupted() async throws {
        let store = try makeTestStore(), turn = UUID()
        var chat = Conversation()
        chat.messages = [Message(id: turn, role: .user, text: "Synthetic request"),
            Message(role: .assistant, text: "Partial", state: .streaming, providerID: "companion:fixture")]
        try await store.save(chat)
        let local = try await store.loadConversation(chat.id)
        XCTAssertEqual(local.messages.last?.state, .interrupted)
        var record = CompanionRunRecord(turnID: turn, connectionID: "fixture", payload: .object([:]))
        record.jobID = UUID().uuidString; record.status = "running"; record.stopRequested = true
        try await store.saveCompanionRun(record)
        try await store.saveWorkTurn(WorkTurn(id: turn, conversationID: chat.id, userMessageID: turn, backendID: "companion:fixture", goal: "Synthetic"))
        let stopped = try await store.loadConversation(chat.id)
        XCTAssertEqual(stopped.messages.last?.state, .interrupted)
    }
}

private struct SavedComputerFixture: RemoteTaskBackend {
    let store: LocalStore
    let messageID: UUID
    let complete: Bool
    let id = "companion:fixture"
    let networkDestination: String? = nil
    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        AsyncThrowingStream { $0.finish(throwing: AssistantError.incompleteResponse) }
    }
    func runTask(_ request: ModelRequest) -> AsyncThrowingStream<RemoteTaskEvent, any Error> {
        AsyncThrowingStream { output in
            let task = Task {
                do {
                    let identity = try XCTUnwrap(request.workIdentity)
                    if complete {
                        XCTAssertTrue(request.messages.isEmpty, "Sync must not construct or submit a second model prompt")
                        let saved = try await store.companionRun(identity.turnID)
                        XCTAssertNotNil(saved)
                    } else {
                        var run = CompanionRunRecord(turnID: identity.turnID, connectionID: "fixture", payload: .object([:]))
                        run.jobID = UUID().uuidString; run.status = "running"
                        try await store.saveCompanionRun(run)
                    }
                    let messages = [Message(id: messageID, role: .assistant,
                        text: complete ? "The saved result is ready." : "Still working", state: complete ? .complete : .streaming, providerID: id)]
                    try await request.commitRemoteTranscript?(messages, [])
                    output.yield(.transcript(messages))
                    if complete { output.yield(.completed); output.finish() }
                    else { output.finish(throwing: CancellationError()) }
                } catch { output.finish(throwing: error) }
            }
            output.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
