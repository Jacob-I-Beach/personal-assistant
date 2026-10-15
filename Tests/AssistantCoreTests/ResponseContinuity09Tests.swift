import Foundation
import XCTest
@testable import AssistantCore

final class ResponseContinuity09Tests: XCTestCase, @unchecked Sendable {
    func testCatalogDefaultDoesNotHideExpandedCapacityAndSmallModelsStayBounded() throws {
        let data = Data(#"{"models":[{"slug":"gpt-6-astra","display_name":"Astra","visibility":"list","context_window":272000,"max_context_window":1050000},{"slug":"smaller","display_name":"Smaller","visibility":"list","context_window":128000,"max_context_window":268384}]}"#.utf8)
        let models = try ChatGPTModel.catalog(from: data)
        let large = ModelContextBudget(model: models[0].id, advertisedWindow: models[0].contextWindow, advertisedMaximumWindow: models[0].maximumContextWindow, requestedInputTokens: 1_000_000)
        XCTAssertEqual(large.selectedInputTokens, 1_000_000); XCTAssertEqual(large.outputReserve, 128_000)
        let small = ModelContextBudget(model: models[1].id, advertisedWindow: models[1].contextWindow, advertisedMaximumWindow: models[1].maximumContextWindow, requestedInputTokens: 1_000_000)
        XCTAssertEqual(small.maximumInputTokens, 252_000); XCTAssertFalse(small.presets.contains(1_000_000))
        XCTAssertEqual(ModelContextBudget(model: "gpt-6-astra", advertisedWindow: 272_000).maximumInputTokens, 1_000_000)
        XCTAssertEqual(ModelContextBudget(model: "gpt-6-astra", advertisedWindow: 272_000, advertisedMaximumWindow: 872_000).modelWindow, 872_000)
    }
    func testAnsweredQuestionRemainsVisibleBeforeTheUserAnswer() {
        let call = ToolCall(id: "question", name: "request_input", arguments: .object(["question": .string("Which time?")]))
        var assistant = Message(role: .assistant, text: ""); assistant.toolCalls = [call]
        let receipt = Message(role: .tool, text: #"{"question":"Which time?","status":"answered","answer":"Morning"}"#, toolCallID: "question")
        let answer = Message(role: .user, text: "Morning")
        let items = ChatTimeline.items([assistant, receipt, answer])
        XCTAssertEqual(items.count, 2); XCTAssertFalse(items[0].isActivity)
        XCTAssertEqual(items[0].messages.first?.id, receipt.id); XCTAssertEqual(items[1].messages.first?.id, answer.id)
    }
    func testManualContinueSurvivesTheOldLifetimeLimitsWithoutEnablingAutomaticLoops() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LocalStore(root: root)
        var chat = Conversation(); let user = Message(role: .user, text: "Finish the saved task")
        chat.messages = [user]; try await store.save(chat)
        var work = WorkTurn(id: user.id, conversationID: chat.id, userMessageID: user.id, backendID: FinishBackend().id, goal: user.text)
        work.phase = .interrupted; work.resumes = 3; work.rounds = 12
        try await store.saveWorkTurn(work)
        do {
            for try await _ in AssistantEngine(store: store).resume(conversation: chat, turnID: work.id, backend: FinishBackend(), automatic: true) {}
            XCTFail("Automatic recovery must remain bounded")
        } catch {}
        for try await _ in AssistantEngine(store: store).resume(conversation: chat, turnID: work.id, backend: FinishBackend()) {}
        let final = try await store.workTurn(work.id)
        XCTAssertEqual(final?.phase, .completed); XCTAssertEqual(final?.resumes, 4)
        XCTAssertEqual(final?.rounds, 13); XCTAssertEqual(final?.automaticResumes, 0)
    }
    func testHealthCatalogAndReadsHaveExplicitBoundaries() throws {
        XCTAssertGreaterThan(HealthDataCatalog.entries.count, 200)
        XCTAssertEqual(Set(HealthDataCatalog.entries.map(\.id)).count, HealthDataCatalog.entries.count)
        XCTAssertTrue(HealthDataCatalog.matching("sleep").contains { $0.id == "HKCategoryTypeIdentifierSleepAnalysis" })
        let valid = try HealthDataQuery(typeIDs: ["HKQuantityTypeIdentifierHeartRate"], start: "2026-10-01T00:00:00Z", end: "2026-10-08T00:00:00Z", mode: "latest", limit: 100)
        XCTAssertEqual(valid.limit, 1)
        XCTAssertThrowsError(try HealthDataQuery(typeIDs: ["unlisted"], start: "2026-10-01T00:00:00Z", end: "2026-10-08T00:00:00Z", mode: "samples", limit: 5))
        XCTAssertThrowsError(try HealthDataQuery(typeIDs: ["workouts"], start: "2020-01-01T00:00:00Z", end: "2026-10-08T00:00:00Z", mode: "samples", limit: 5))
        XCTAssertThrowsError(try HealthDataQuery(typeIDs: ["workouts"], start: "2026-10-01T00:00:00Z", end: "2026-10-08T00:00:00Z", mode: "samples", limit: 50_000))
    }
}
private struct FinishBackend: ModelBackend {
    let id = "synthetic-manual-recovery-09"
    var networkDestination: String? { nil }
    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        AsyncThrowingStream { output in output.yield(.textDelta("The saved task is complete.")); output.yield(.completed); output.finish() }
    }
}
