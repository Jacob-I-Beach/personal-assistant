import AssistantCore
import XCTest
@testable import PersonalAssistant

@MainActor
final class PushWardPlatformTests: XCTestCase {
    func testBridgeAttentionDoesNotDependOnTheNativePushEntitlement() async throws {
        let controller = ReplyLiveActivity()
        let client = try CompanionClient(baseURL: URL(string: "https://127.0.0.1:1")!, fingerprint: String(repeating: "a", count: 64), token: "synthetic")
        controller.begin(conversationID: UUID(), modelName: "Synthetic", computer: true, reconnecting: false, externalPresentation: true)
        controller.attach(jobID: UUID().uuidString, client: client, notifications: true, externalPresentation: true)
        XCTAssertTrue(controller.remoteNotificationsAvailable)
        await controller.finish(completed: false, detached: true)
        XCTAssertTrue(controller.remoteNotificationsAvailable, "Detaching the phone must not disable server alerts")
        controller.begin(conversationID: UUID(), modelName: "Synthetic", computer: true, reconnecting: false, externalPresentation: true)
        controller.attach(jobID: UUID().uuidString, client: client, notifications: false, externalPresentation: true)
        XCTAssertFalse(controller.remoteNotificationsAvailable)
    }
    func testProviderHintIsBoundToThePairedProfileAndOldCachesStillDecode() throws {
        let connection = CompanionConnection(baseURL: URL(string: "https://127.0.0.1:1")!, certificateSHA256: String(repeating: "a", count: 64),
            serverID: "fixture", deviceID: "phone", profileID: "profile", name: "Fixture")
        let profile: JSONValue = .object(["status": .string("connected"), "sharing": .bool(true), "profileId": .string("profile")])
        let record = try ComputerAccountRecord(connection: connection, profile: profile, activityProvider: "pushward")
        XCTAssertEqual(record.activityProvider, "pushward")
        var value = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        value.removeValue(forKey: "activityProvider")
        let old = try JSONDecoder().decode(ComputerAccountRecord.self, from: JSONSerialization.data(withJSONObject: value))
        XCTAssertNil(old.activityProvider)
        let changed: JSONValue = .object(["status": .string("connected"), "sharing": .bool(true), "profileId": .string("another-profile")])
        XCTAssertNil(try ComputerAccountRecord(connection: connection, profile: changed, activityProvider: "pushward").activityProvider)
    }
}
