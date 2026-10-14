import Foundation

public enum ToolCapability {
    public static func describe(_ tool: ToolDefinition, compact: Bool = false) -> JSONValue {
        let readOnly = ["get_capabilities", "find_tools", "read_capture", "inspect_depth", "search_history", "read_history", "list_conversations", "read_conversation", "read_task", "search_workspace", "read_workspace", "read_memory", "get_device_info", "get_current_location", "list_workspaces", "list_files", "read_file", "search_files", "get_file_metadata"]
        let reviewed = ["get_current_location", "prepare_route", "prepare_calendar_event", "compose_text_message", "prepare_phone_call", "open_in_maps", "export_artifact", "connect_workspace", "apply_file_edit"]
        let surfaceReadOnly = ["get_surface_schema", "read_surface", "read_route", "get_app_context", "read_inbox", "read_schedule", "find_available_time", "read_reminders", "list_planning_sources", "read_artifact_revision", "find_contacts", "search_context", "read_project"].contains(tool.name)
        let extraReview = ["request_input", "save_calendar_event", "save_reminder", "complete_reminder", "delete_planning_item", "apply_planning_changes", "read_health_data", "read_health_overview", "compose_email", "compose_message_with_files", "share_files", "schedule_assistant_task"].contains(tool.name)
        let healthReadOnly = ["list_health_types", "read_health_data", "read_health_overview"].contains(tool.name)
        if tool.name == "read_tool_result" { return .object(["name": .string(tool.name), "read_only": .bool(true), "native_review": .bool(false)]) }
        if compact {
            return .object(["name": .string(tool.name), "read_only": .bool(readOnly.contains(tool.name) || surfaceReadOnly || healthReadOnly), "native_review": .bool(reviewed.contains(tool.name) || extraReview)])
        }
        return .object(["name": .string(tool.name), "description": .string(tool.description),
                        "read_only": .bool(readOnly.contains(tool.name) || surfaceReadOnly || healthReadOnly),
                        "native_review": .bool(reviewed.contains(tool.name) || extraReview),
                        "execution_location": .string(tool.name == "prepare_route" ? "on-device with Apple Maps network services" : "on-device"),
                        "foreground_required": .bool(reviewed.contains(tool.name) || extraReview),
                        "scope": .string(tool.name.contains("file") || tool.name.contains("workspace")
                            ? "Attached/permitted Library data or a connected folder explicitly enabled for this conversation and model location."
                            : "The current conversation and permissions described by this tool.")])
    }
}
