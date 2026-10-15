import AssistantCore
import Foundation
import XCTest
@testable import PersonalAssistant

@MainActor final class ContinuityPlatformTests: XCTestCase {
    private var connection: CompanionConnection {
        .init(baseURL: URL(string: "https://127.0.0.1:1")!, certificateSHA256: String(repeating: "a", count: 64), serverID: "fixture", deviceID: "fixture-phone", profileID: "original-profile", name: "Fixture")
    }
    func testProductionRouteChoosesPCOnlyWhenOriginalAccountIsReady() async throws {
        var preference = ModelSettings(); preference.choice = .chatGPT; preference.useComputer = true; preference.companion = connection
        preference.chatGPTAccountID = "mobile-profile"; preference.chatGPTModel = "chosen-model"
        let online = try await ChatGPTRouting.select(preference, mobileReady: true) { _ in .object(["profile": .object(["status": .string("connected"), "sharing": .bool(true), "profileId": .string("original-profile")])]) }
        XCTAssertTrue(online.selection.useComputer); XCTAssertEqual(online.selection.chatGPTModel, "chosen-model")
        let offline = try await ChatGPTRouting.select(preference, mobileReady: true) { _ in throw URLError(.cannotConnectToHost) }
        XCTAssertFalse(offline.selection.useComputer); XCTAssertEqual(offline.selection.chatGPTAccountID, "mobile-profile")
        XCTAssertTrue(preference.useComputer, "Per-request fallback must not overwrite the preference")
        let different = try await ChatGPTRouting.select(preference, mobileReady: true) { _ in .object(["profile": .object(["status": .string("connected"), "sharing": .bool(true), "profileId": .string("different-profile")])]) }
        XCTAssertFalse(different.selection.useComputer)
    }
    func testMobileFallbackIdentityAndFirstSignInKeepTheContextChoice() async throws {
        let model = AppModel(); try await model.waitUntilReady()
        var preference = ModelSettings(); preference.choice = .chatGPT; preference.useComputer = true; preference.companion = connection; preference.chatGPTModel = "gpt-6.1-sol"
        preference.contextTokensByModel[preference.contextPreferenceKey] = 1_000_000
        model.settings = preference; model.adoptMobileAccount("mobile-fixture")
        XCTAssertEqual(model.settings.contextTokensByModel[model.settings.contextPreferenceKey], 1_000_000)
        model.accounts = [.init(id: "mobile-fixture", label: "mobile@example.test", isConnected: true)]
        try model.applyComputerAccount(.object(["status": .string("disconnected"), "sharing": .bool(false), "profileId": .string(connection.profileID)]), connection: connection)
        XCTAssertTrue(model.prefersComputerChatGPT); XCTAssertFalse(model.usesComputerChatGPT)
        XCTAssertEqual(model.chatGPTAccountLabel, "mobile@example.test"); XCTAssertFalse(model.shouldOfferChatGPTSignIn)
        XCTAssertEqual(model.modelCatalog.owner, "account:mobile-fixture")
    }
    func testDisabledPCIsNotProbedAndMissingMobileAccountDoesNotFabricateLogin() async throws {
        var preference = ModelSettings(); preference.choice = .chatGPT; preference.useComputer = false; preference.companion = connection
        let mobile = try await ChatGPTRouting.select(preference, mobileReady: true) { _ in XCTFail("Disabled PC must not be probed"); return .null }
        XCTAssertFalse(mobile.selection.useComputer)
        do { _ = try await ChatGPTRouting.select(preference, mobileReady: false) { _ in XCTFail("No PC request"); return .null }; XCTFail("Mobile login is required") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Connect ChatGPT")) }
    }
    func testComputerQuestionStagesWithoutAReviewWaiterOrBlockingIndependentWork() async throws {
        let model = AppModel(); try await model.waitUntilReady(); let store = try XCTUnwrap(model.store)
        let turn = UUID(), chat = UUID()
        var conversation = Conversation(id: chat); conversation.messages = [Message(id: turn, role: .user, text: "Synthetic task")]
        try await store.save(conversation)
        try await store.saveWorkTurn(WorkTurn(id: turn, conversationID: chat, userMessageID: turn, backendID: "companion:fixture", destination: connection.destination, goal: "Synthetic task"))
        let call = ToolCall(id: "synthetic-question", name: "request_input", arguments: .object(["question": .string("Which label?"), "why": .string("Only the final label depends on this answer."), "kind": .string("choice"), "choices_json": .string("[\"Blue\",\"Green\"]")]))
        let broker = AssistantTools(store: store, conversationID: chat, captureIDs: [], sandbox: JavaScriptSandbox(), remote: true, operationScope: turn, additionalDefinitions: [QuestionTools.request], additionalExecutor: { call in try await model.executeQuestionTool(call, conversationID: chat) })
        let result = try await broker.execute(call)
        XCTAssertEqual(result.output["status"], .string("pending_input")); XCTAssertNil(model.nativeAction)
        let questions = try await store.pendingQuestions(); let first = try XCTUnwrap(questions.first { $0.turnID == turn })
        let again = try await broker.execute(call)
        XCTAssertEqual(again.output["question_id"], .string(first.id.uuidString))
        let saved = try await store.pendingQuestions(); XCTAssertEqual(saved.filter { $0.turnID == turn }.count, 1)
    }
    func testCompactionReserveUsesSameLocalBudgetAsResponseSettings() {
        let budget = LocalInferenceBudget(weightBytes: 2_370_000_000, availableBytes: 8_000_000_000, requestedMemoryGiB: 8, requestedContextTokens: 65_536, supportsEfficientKV: true, optimizedTextRuntime: true)
        XCTAssertEqual(budget.compactionReserveTokens, 19_661)
        XCTAssertEqual(budget.workingInputTokens + budget.compactionReserveTokens, budget.inputTokens)
        XCTAssertEqual(AppleModelBackend(location: .device).contextLimits.compactionReserveBytes, 3000)
        XCTAssertTrue(AppleModelBackend(location: .device).supportsContextCheckpoints)
    }
    func testReportedCatalogWindowUsesTheSameBudgetForPCAndMobile() async throws {
        let model = AppModel(); try await model.waitUntilReady()
        model.chatGPTModels = try ChatGPTModel.catalog(from: Data(#"{"models":[{"slug":"gpt-6.1-sol","display_name":"GPT-6.1-Sol","visibility":"list","max_context_window":872000}]}"#.utf8))
        for useComputer in [false, true] {
            var selection = ModelSettings(); selection.choice = .chatGPT; selection.chatGPTModel = "gpt-6.1-sol"
            selection.chatGPTAccountID = "synthetic"; selection.useComputer = useComputer; selection.companion = connection
            selection.contextTokensByModel[selection.contextPreferenceKey] = 855_616
            let plan = try XCTUnwrap(model.contextBudget(for: selection))
            XCTAssertEqual(plan.outputReserve, 128_000)
            XCTAssertEqual(plan.activeInputTokens, 598_931)
            XCTAssertEqual(plan.compactionOutputReserve, 16_384)
        }
    }
    func testLocalAnswerToolStoresExactSourceWithoutStartingComputerWork() async throws {
        let model = AppModel(); try await model.waitUntilReady(); let store = try XCTUnwrap(model.store)
        let earlier = UUID(), current = UUID()
        var chat = Conversation(); chat.messages = [Message(id: earlier, role: .user, text: "Prepare a report"), Message(id: current, role: .user, text: "Use Blue")]
        try await store.save(chat)
        try await store.saveWorkTurn(WorkTurn(id: earlier, conversationID: chat.id, userMessageID: earlier, backendID: "companion:fixture", goal: "Report"))
        try await store.saveWorkTurn(WorkTurn(id: current, conversationID: chat.id, userMessageID: current, backendID: "apple:on-device", goal: "Use Blue"))
        let question = try await store.saveQuestion(TaskQuestion(conversationID: chat.id, turnID: earlier, callID: "q", title: "Which label?", detail: "Only the label is pending", kind: .choice, choices: ["Blue"]))
        let chatID = chat.id
        let broker = AssistantTools(store: store, conversationID: chatID, captureIDs: [], sandbox: JavaScriptSandbox(), operationScope: current, additionalDefinitions: QuestionTools.definitions,
            additionalExecutor: { call in try await model.executeQuestionAnswerTool(call, conversationID: chatID, destination: nil) })
        let result = try await broker.execute(ToolCall(id: "answer", name: "answer_task_question", arguments: .object(["question_id": .string(question.id.uuidString), "answer_quote": .string("Blue")])))
        XCTAssertTrue(result.succeeded); XCTAssertEqual(result.output["status"], .string("answer_saved"))
        let saved = try await store.question(question.id); XCTAssertEqual(saved.answerSourceMessageID, current)
        XCTAssertNil(AppModel.questionResult(saved, callID: "q", name: "request_input").userResponse, "The existing user message must not be duplicated in an older turn")
        XCTAssertFalse(model.isRunning); XCTAssertNil(model.nativeAction)
    }
}
