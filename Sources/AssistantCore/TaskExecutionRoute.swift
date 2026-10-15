import Foundation

public enum TaskExecutionRoute: String, Codable, Sendable { case computer, mobile, onDevice }
public enum TaskRoutePolicy {
    /// Only NEW requests are routed here. Existing work is bound to its saved
    /// backend identity even if a toggle, network or account changes later.
    public static func newRequest(local: Bool, computerEnabled: Bool, computerReady: Bool, mobileReady: Bool) throws -> TaskExecutionRoute {
        if local { return .onDevice }
        if computerEnabled && computerReady { return .computer }
        if mobileReady { return .mobile }
        throw AssistantError.provider(computerEnabled ? "Your computer is unavailable and mobile ChatGPT is not connected. Connect ChatGPT on this iPhone; your draft is saved." : "Connect ChatGPT on this iPhone to use mobile mode. Your draft is saved.")
    }
    public static func savedOwner(backendID: String, destination: String?) -> TaskExecutionRoute {
        if backendID.hasPrefix("companion:") { return .computer }
        return destination == nil ? .onDevice : .mobile
    }
}
