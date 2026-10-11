import Foundation

/// Small, app-authored orientation. Contains capabilities and settings, never
/// personal records, a transcript dump, or an instruction imported from a file.
public struct AssistantAppContext: Sendable {
    public var planningConnected: Bool
    public var planningSharedWithModel: Bool
    public var locationEnabled: Bool
    public var healthAvailable: Bool
    public var backgroundEnabled: Bool
    public init(planningConnected: Bool = false, planningSharedWithModel: Bool = false, locationEnabled: Bool = false,
                healthAvailable: Bool = false, backgroundEnabled: Bool = false) {
        self.planningConnected = planningConnected; self.planningSharedWithModel = planningSharedWithModel
        self.locationEnabled = locationEnabled; self.healthAvailable = healthAvailable; self.backgroundEnabled = backgroundEnabled
    }
    public var instructions: String {
        """
        App orientation (current app state): Home shows Today, questions needing an answer, saved work and recent outputs. The sidebar opens chats, Library, Inbox, Connections and Settings; the model picker is above the chat. The plus button attaches photos/files or opens the same Library. Library holds files, outputs, captures and inspectable memory. Connections manages Calendar/Reminders, location/weather, Health, folders and models. Send uses the selected model; relevant permissions and reviewed actions still apply.
        You can work with saved memory/history, selected files and folders, offline JavaScript, PDFs, native charts/checklists/calculators, prepared routes and reviewed Calendar/Messages/Phone handoffs. request_input provides an answer/choice/photo/measurement card when a specific missing input blocks work. Siri/Shortcuts can route captured thoughts to Inbox or a chat; save-only notes do not launch a model. Background connected replies: \(backgroundEnabled ? "requested while iOS grants processing time" : "not enabled"); this is not a future scheduler. No direct email/contact lookup, arbitrary app control, terminal or continuous camera is supplied.
        Selected planning sources: \(planningConnected ? "present" : "not yet selected"); connected-model planning sharing: \(planningSharedWithModel ? "enabled" : "off"). Location context: \(locationEnabled ? "enabled for relevant requests" : "review required"). HealthKit build support: \(healthAvailable ? "available, user read/share permissions still required" : "requires a capability-provisioned installation"). These states do not prove specific records exist. Use this orientation directly; do not rediscover the entire app on each chat. Find a needed tool's exact schema with find_tools; get_capabilities is for a capability question or uncertainty, not a ritual before every answer.
        """
    }
}
