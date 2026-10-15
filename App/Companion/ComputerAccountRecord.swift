import Foundation
import AssistantCore

/// Display metadata from the paired computer. Never contains OAuth credentials.
struct ComputerAccountRecord: Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable { case connected, connecting, signInRequired, sharingOff, accountChanged }
    let serverID: String
    let deviceID: String
    let profileID: String
    let email: String?
    let name: String?
    let status: Status
    let activityProvider: String?

    init(connection: CompanionConnection, profile: JSONValue, activityProvider: String? = nil) throws {
        guard let rawStatus = profile["status"]?.stringValue,
              ["connected", "connecting", "disconnected", "reauth_required"].contains(rawStatus) else {
            throw AssistantError.provider("The computer did not return its account status.")
        }
        serverID = connection.serverID; deviceID = connection.deviceID; profileID = connection.profileID
        let reportedProfile = profile["profileId"]?.stringValue
        let matches = reportedProfile == connection.profileID
        self.activityProvider = matches && activityProvider == "pushward" ? "pushward" : nil
        email = matches ? Self.displayValue(profile["identity"]?["email"]?.stringValue) : nil
        name = matches ? Self.displayValue(profile["identity"]?["name"]?.stringValue) : nil
        if let reportedProfile, reportedProfile != connection.profileID { status = .accountChanged }
        else if rawStatus == "connected" && !matches { status = .signInRequired }
        else if rawStatus == "connected" { status = profile["sharing"] == .bool(true) ? .connected : .sharingOff }
        else if rawStatus == "connecting" { status = .connecting }
        else { status = .signInRequired }
    }
    func matches(_ connection: CompanionConnection) -> Bool {
        serverID == connection.serverID && deviceID == connection.deviceID && profileID == connection.profileID
    }
    var label: String { email ?? name ?? "Your ChatGPT account" }
    var isConnected: Bool { status == .connected }
    var needsAttention: Bool { status != .connected && status != .connecting }
    var detail: String {
        switch status {
        case .connected: "Connected · using your ChatGPT plan"
        case .connecting: "Finishing sign-in on your computer"
        case .signInRequired: "Sign in to ChatGPT on your computer"
        case .sharingOff: "Enable ChatGPT sharing on your computer"
        case .accountChanged: "The account on your computer changed. Update this connection."
        }
    }
    private static func displayValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let clean = value.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return clean.isEmpty ? nil : String(clean.prefix(320))
    }
}

enum ComputerAccountReachability: Equatable { case unchecked, checking, reachable, unavailable, unready }
