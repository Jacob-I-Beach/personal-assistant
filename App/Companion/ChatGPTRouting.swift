import AssistantCore
import Foundation

@MainActor enum ChatGPTRouting {
    struct Resolution { let selection: ModelSettings; let observation: JSONValue? }
    static func select(_ preference: ModelSettings, mobileReady: Bool,
                       probe: (CompanionConnection) async throws -> JSONValue) async throws -> Resolution {
        guard preference.choice == .chatGPT, !preference.localOnly else { return .init(selection: preference, observation: nil) }
        var observation: JSONValue?, computerReady = false
        if preference.useComputer, let connection = preference.companion {
            observation = try? await probe(connection)
            computerReady = observation?["profile"]?["status"] == .string("connected") && observation?["profile"]?["sharing"] == .bool(true)
                && observation?["profile"]?["profileId"] == .string(connection.profileID)
        }
        let route = try TaskRoutePolicy.newRequest(local: false, computerEnabled: preference.useComputer, computerReady: computerReady, mobileReady: mobileReady)
        var selection = preference; selection.useComputer = route == .computer
        return .init(selection: selection, observation: observation)
    }
}
