import Foundation

public enum ToolCapability {
    public static func describe(_ tool: ToolDefinition, compact: Bool = false) -> JSONValue {
        let readOnly = ["get_capabilities", "find_tools", "read_capture", "search_history", "read_history", "search_workspace", "read_workspace", "read_memory", "get_device_info", "get_current_location", "list_workspaces", "list_files", "read_file", "search_files", "get_file_metadata"]
        let reviewed = ["get_current_location", "prepare_calendar_event", "compose_text_message", "prepare_phone_call", "open_in_maps", "export_artifact", "connect_workspace", "apply_file_edit"]
        if compact {
            return .object(["name": .string(tool.name), "read_only": .bool(readOnly.contains(tool.name)), "native_review": .bool(reviewed.contains(tool.name))])
        }
        return .object(["name": .string(tool.name), "description": .string(tool.description),
                        "read_only": .bool(readOnly.contains(tool.name)),
                        "native_review": .bool(reviewed.contains(tool.name)),
                        "execution_location": .string("on-device"),
                        "foreground_required": .bool(reviewed.contains(tool.name)),
                        "scope": .string(tool.name.contains("file") || tool.name.contains("workspace")
                            ? "Attached/permitted Library data or a connected folder explicitly enabled for this conversation and model location."
                            : "The current conversation and permissions described by this tool.")])
    }
}
