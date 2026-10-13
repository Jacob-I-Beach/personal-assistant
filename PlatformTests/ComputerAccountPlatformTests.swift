import AssistantCore
import XCTest
@testable import PersonalAssistant

@MainActor
final class ComputerAccountPlatformTests: XCTestCase {
    private var connection: CompanionConnection {
        CompanionConnection(baseURL: URL(string: "https://127.0.0.1:1")!, certificateSHA256: String(repeating: "a", count: 64),
            serverID: "synthetic-server", deviceID: "synthetic-phone", profileID: "synthetic-profile", name: "Test computer")
    }
    private func profile(_ status: String = "connected", sharing: Bool = true, id: String = "synthetic-profile") -> JSONValue {
        .object(["status": .string(status), "sharing": .bool(sharing), "profileId": .string(id),
            "identity": .object(["email": .string("fixture@example.test"), "name": .string("Fixture")]),
            "access_token": .string("synthetic-do-not-cache")])
    }
    func testAuthenticatedIdentityIsBoundToThePairedAccountAndCachesNoCredentials() throws {
        let record = try ComputerAccountRecord(connection: connection, profile: profile())
        XCTAssertTrue(record.isConnected); XCTAssertEqual(record.label, "fixture@example.test")
        let data = try JSONEncoder().encode(record)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("synthetic-do-not-cache"))
        XCTAssertEqual(try JSONDecoder().decode(ComputerAccountRecord.self, from: data), record)
        var other = connection; other.deviceID = "another-phone"
        XCTAssertFalse(record.matches(other))
        let changed = try ComputerAccountRecord(connection: connection, profile: profile(id: "another-profile"))
        XCTAssertEqual(changed.status, .accountChanged); XCTAssertNil(changed.email); XCTAssertNil(changed.name)
    }
    func testSharingAndAuthenticationAreDifferentStates() throws {
        XCTAssertEqual(try ComputerAccountRecord(connection: connection, profile: profile(sharing: false)).status, .sharingOff)
        XCTAssertEqual(try ComputerAccountRecord(connection: connection, profile: profile("reauth_required")).status, .signInRequired)
        XCTAssertEqual(try ComputerAccountRecord(connection: connection, profile: profile("connecting")).status, .connecting)
        XCTAssertThrowsError(try ComputerAccountRecord(connection: connection, profile: .object([:])))
    }
    func testSavedTaskUsesOriginalModelWithoutChangingTheNextMessageSelection() throws {
        let turn = UUID()
        let work = WorkTurn(id: turn, conversationID: UUID(), userMessageID: turn, backendID: "companion:fixture", destination: connection.destination, goal: "Synthetic")
        let record = CompanionRunRecord(turnID: turn, connectionID: connection.destination,
            payload: .object(["body": .object(["model": .string("original-model")])]))
        var current = ModelSettings(); current.companion = connection; current.useComputer = true; current.localOnly = false
        current.choice = .appleOnDevice; current.chatGPTModel = "next-model"
        let restored = try ComputerTaskRecovery.selection(for: work, record: record, current: current)
        XCTAssertEqual(restored.choice, .chatGPT); XCTAssertEqual(restored.chatGPTModel, "original-model")
        XCTAssertEqual(current.choice, .appleOnDevice); XCTAssertEqual(current.chatGPTModel, "next-model")
        current.localOnly = true
        XCTAssertThrowsError(try ComputerTaskRecovery.selection(for: work, record: record, current: current))
        current.localOnly = false; current.companion?.profileID = "another-account"
        XCTAssertThrowsError(try ComputerTaskRecovery.selection(for: work, record: record, current: current))
    }
}
