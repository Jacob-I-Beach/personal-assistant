import Foundation

public struct ChatTimelineItem: Identifiable, Sendable {
    public let id: UUID
    public var messages: [Message]
    public var isActivity: Bool
}
public enum ChatTimeline {
    public static func toolName(for message: Message, in messages: [Message]) -> String {
        guard let call = messages.reversed().flatMap(\.toolCalls).first(where: { $0.id == message.toolCallID }) else { return "tool" }
        return call.name == "use_tool" ? call.arguments["name"]?.stringValue ?? "tool" : call.name
    }
    public static func items(_ messages: [Message]) -> [ChatTimelineItem] {
        var result: [ChatTimelineItem] = []
        var names: [String: String] = [:]
        for message in messages {
            for call in message.toolCalls { names[call.id] = call.name == "use_tool" ? call.arguments["name"]?.stringValue ?? "tool" : call.name }
            let visible = !message.text.isEmpty || !message.captureIDs.isEmpty || !message.fileIDs.isEmpty || !message.displayParts.isEmpty || message.role == .tool || message.state == .failed || message.state == .interrupted
            guard visible else { continue }
            let name = names[message.toolCallID ?? ""] ?? "tool"
            let activity = message.role == .tool && !["prepare_route", "present_surface", "update_plan", "request_input"].contains(name)
            if activity, result.last?.isActivity == true {
                result[result.count - 1].messages.append(message)
            } else { result.append(ChatTimelineItem(id: message.id, messages: [message], isActivity: activity)) }
        }
        return result
    }
    public static func category(_ name: String) -> String {
        switch name {
        case "search_history", "search_workspace", "read_history", "read_workspace", "list_conversations", "read_conversation": "Earlier conversations & files"
        case "read_memory", "save_memory", "forget_memory": "Memory"
        case "get_capabilities", "find_tools", "get_device_info", "get_app_context": "Available context & tools"
        case "run_javascript": "Calculations"
        case "read_task", "update_plan": "Task progress"
        case "request_input": "Your answers"
        case "list_health_types", "read_health_data", "read_health_overview": "Health"
        case "read_inbox": "Saved captures"
        case "list_planning_sources", "read_schedule", "find_available_time", "read_reminders", "save_calendar_event", "save_reminder", "complete_reminder": "Calendar & Reminders"
        case "create_artifact", "create_pdf", "create_file", "read_file", "list_files", "search_files", "export_artifact", "apply_file_edit", "propose_file_edit": "Files"
        default: "Device actions"
        }
    }
}
