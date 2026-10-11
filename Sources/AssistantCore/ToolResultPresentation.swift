import Foundation

/// Deterministic receipt formatting. No model is asked to paraphrase or re-calculate tool output.
public enum ToolResultPresentation {
    public static func activeTitle(_ call: ToolCall) -> String {
        let name = call.name == "use_tool" ? call.arguments["name"]?.stringValue ?? "" : call.name
        switch name {
        case "get_capabilities", "find_tools": return "Checking available tools"
        case "list_conversations", "search_history", "search_workspace", "read_conversation", "read_history", "read_workspace": return "Looking through saved context"
        case "read_memory": return "Reading saved memory"
        case "save_memory", "forget_memory": return "Updating saved memory"
        case "run_javascript": return "Calculating with JavaScript"
        case "run_python": return "Working with your data on your computer"
        case "inspect_document": return "Inspecting the document and its pages"
        case "find_contacts": return "Finding the right person"
        case "compose_email", "compose_message_with_files", "share_files": return "Preparing your message or files for review"
        case "schedule_assistant_task": return "Preparing scheduled work for review"
        case "update_artifact", "read_artifact_revision": return "Working with the current document"
        case "read_project", "update_project": return "Keeping the project up to date"
        case "search_context": return "Finding relevant saved context"
        case "create_pdf", "create_artifact", "create_file": return "Creating your file"
        case "read_capture", "inspect_depth": return "Inspecting the saved image"
        case "prepare_route", "read_route": return "Preparing directions"
        case "prepare_calendar_event", "compose_text_message", "prepare_phone_call", "open_in_maps", "apply_file_edit": return "Preparing your review"
        case "connect_workspace", "list_files", "search_files", "read_file": return "Working with your folder"
        case "present_surface", "update_surface": return "Updating your working object"
        case "get_current_location": return "Reading your location"
        case "get_device_info", "get_app_context": return "Checking device context"
        case "request_input": return "Waiting for your answer"
        case "read_inbox": return "Reading saved captures"
        case "read_schedule", "find_available_time": return "Checking your schedule"
        case "read_reminders", "list_planning_sources": return "Checking your planning context"
        case "save_calendar_event", "save_reminder", "complete_reminder", "delete_planning_item", "apply_planning_changes": return "Preparing a change for review"
        case "export_artifact": return "Preparing export"
        default: return "Working on your request"
        }
    }
    public static func summary(tool: String, output: JSONValue) -> [Field] {
        func count(_ key: String, label: String) -> Field? { output[key]?.arrayValue.map { Field(label: label, value: $0.isEmpty ? "None in this result" : String($0.count)) } }
        switch tool {
        case "search_workspace": return [count("messages", label: "Matching messages"), count("files", label: "Files"), count("artifacts", label: "Created files")].compactMap { $0 }
        case "list_conversations": return [count("conversations", label: "Available chats")].compactMap { $0 }
        case "read_conversation": return [count("messages", label: "Messages read")].compactMap { $0 }
        case "read_memory": return [count("result", label: "Current memories")].compactMap { $0 }
        case "get_capabilities":
            return [count("tools", label: "Available tools"), output["workspace_search_enabled"]?.boolValue.map { Field(label: "Other app chats", value: $0 ? "Search enabled" : "Enable workspace search in Settings") },
                output["automatic_memory_enabled"]?.boolValue.map { Field(label: "Automatic memory", value: $0 ? "Enabled · history and undo in Library" : "Off") }].compactMap { $0 }
        case "read_task":
            return [output["goal"]?.stringValue.map { Field(label: "Request", value: String($0.prefix(350))) }, output["phase"]?.stringValue.map { Field(label: "Reply", value: $0.capitalized) }, count("actions", label: "Action receipts")].compactMap { $0 }
        default: return []
        }
    }
    public struct Field: Equatable, Sendable, Identifiable {
        public var label: String
        public var value: String
        public var id: String { label }
    }
    public static func fields(_ value: JSONValue) -> [Field] {
        if let object = value.objectValue {
            return object.keys.sorted().prefix(24).map { Field(label: label($0), value: display(object[$0]!)) }
        }
        return [Field(label: "Result", value: display(value))]
    }
    public static func label(_ key: String) -> String {
        let spaced = key.replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ")
        guard let first = spaced.first else { return "Value" }
        return String(first).uppercased() + spaced.dropFirst()
    }
    public static func display(_ value: JSONValue) -> String {
        switch value {
        case .string(let text): return text.isEmpty ? "Empty text" : String(text.prefix(300))
        case .number(let number):
            guard number.isFinite else { return "Non-finite number" }
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.numberStyle = (abs(number) > 0 && abs(number) < 0.000001) || abs(number) >= 1e12 ? .scientific : .decimal
            formatter.usesGroupingSeparator = formatter.numberStyle == .decimal
            formatter.groupingSize = 3; formatter.secondaryGroupingSize = 3
            formatter.groupingSeparator = ","; formatter.decimalSeparator = "."
            formatter.usesSignificantDigits = true; formatter.maximumSignificantDigits = 10
            return formatter.string(from: NSNumber(value: number)) ?? String(number)
        case .bool(let flag): return flag ? "Yes" : "No"
        case .null: return "No value"
        case .array(let values):
            guard !values.isEmpty else { return "No items" }
            if values.allSatisfy({ $0.objectValue == nil && $0.arrayValue == nil }) {
                let preview = values.prefix(6).map(display).joined(separator: " · ")
                return preview + (values.count > 6 ? " · +\(values.count - 6) more" : "")
            }
            return "\(values.count) items"
        case .object(let object): return "\(object.count) fields"
        }
    }
    public static func arguments(of call: ToolCall?) -> JSONValue? {
        guard let call else { return nil }
        return call.name == "use_tool" ? (try? CompactToolInvocation.values(from: call.arguments)) : call.arguments
    }
}
