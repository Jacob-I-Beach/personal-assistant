import AssistantCore
import XCTest
@testable import PersonalAssistant

@MainActor final class LocalIsolationPlatformTests: XCTestCase {
    func testNewAppleRequestUsesTheOnDeviceBackendEvenWithComputerEnabled() async throws {
        let model = AppModel()
        try await model.waitUntilReady()
        var selection = ModelSettings(); selection.choice = .appleOnDevice; selection.useComputer = true
        selection.companion = CompanionConnection(baseURL: URL(string: "https://127.0.0.1:1")!, certificateSHA256: String(repeating: "a", count: 64),
            serverID: "fixture", deviceID: "phone", profileID: "profile", name: "Fixture")
        let backend = try await model.backend(for: selection, onComputer: true)
        XCTAssertEqual(backend.id, "apple:on-device")
        XCTAssertNil(backend.networkDestination)
        XCTAssertFalse(backend is any RemoteTaskBackend)
        XCTAssertEqual(backend.contextLimits.maximumTextBytes, ContextLimits.appleOnDevice.maximumTextBytes)
        XCTAssertEqual(UILocalIsolationBackend().contextLimits.maximumTextBytes, backend.contextLimits.maximumTextBytes)
    }
    func testLocalSelectionsCannotRecoverAnOlderComputerModel() throws {
        let connection = CompanionConnection(baseURL: URL(string: "https://127.0.0.1:1")!, certificateSHA256: String(repeating: "a", count: 64),
            serverID: "fixture", deviceID: "phone", profileID: "profile", name: "Fixture")
        let turn = UUID()
        let work = WorkTurn(id: turn, conversationID: UUID(), userMessageID: turn, backendID: "companion:fixture", destination: connection.destination, goal: "Synthetic")
        let record = CompanionRunRecord(turnID: turn, connectionID: connection.destination, payload: .object(["body": .object(["model": .string("original-model")])]))
        var settings = ModelSettings(); settings.companion = connection; settings.useComputer = true
        for choice in [ModelChoice.appleOnDevice, .localMLX, .appleCloud, .openAI, .compatibleServer] {
            settings.choice = choice
            XCTAssertThrowsError(try ComputerTaskRecovery.selection(for: work, record: record, current: settings))
        }
        settings.choice = .chatGPT; settings.chatGPTModel = "next-model"
        XCTAssertEqual(try ComputerTaskRecovery.selection(for: work, record: record, current: settings).chatGPTModel, "original-model")
        XCTAssertEqual(settings.chatGPTModel, "next-model")
    }
    func testPausedPresentationIgnoresOldBridgeHints() async throws {
        XCTAssertFalse(TaskPresentationPolicy.isEnabled)
        let controller = ReplyLiveActivity()
        let client = try CompanionClient(baseURL: URL(string: "https://127.0.0.1:1")!, fingerprint: String(repeating: "a", count: 64), token: "synthetic")
        controller.begin(conversationID: UUID(), modelName: "Synthetic", computer: true, reconnecting: true, externalPresentation: true)
        controller.attach(jobID: UUID().uuidString, client: client, notifications: true, externalPresentation: true)
        await controller.finish(completed: true, detached: false)
        XCTAssertFalse(controller.remoteNotificationsAvailable)
    }
}
