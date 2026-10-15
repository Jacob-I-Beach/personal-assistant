import Foundation

/// Small, evidence-based labels shared by the transcript and live progress.
/// This formats observed actions; it never asks another model to invent a summary.
public struct ActivitySummary: Equatable, Sendable {
    public var title: String
    public var detail: String
    public var symbol: String
    public var running: Bool = false
    public var needsAttention: Bool = false
}

public enum ActivitySummaries {
    public static func compact(_ text: String, limit: Int = 76) -> String {
        let value = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return value.count > limit ? String(value.prefix(limit - 1)) + "…" : value
    }
    public static func web(_ activities: [WebActivity]) -> ActivitySummary {
        let running = activities.contains(where: \.isRunning)
        let incomplete = activities.contains { !$0.isRunning && !$0.isSuccessful }
        let searches = activities.filter { $0.action != "open_page" && $0.action != "find_in_page" }.count
        let pages = activities.filter { $0.action == "open_page" }.count
        let finds = activities.filter { $0.action == "find_in_page" }.count
        let queries = activities.flatMap(\.queries)
        let sources = Set(activities.flatMap(\.sources).map(\.url))
        var title: String
        if activities.count == 1, let activity = activities.first {
            if activity.action == "open_page", let page = activity.sources.first {
                title = (running ? "Reading " : "Read ") + compact(page.title.isEmpty ? page.url.host ?? "a web page" : page.title)
            } else if activity.action == "find_in_page", let pattern = activity.pattern {
                title = (running ? "Finding “" : "Looked for “") + compact(pattern) + "”"
            } else if let query = queries.first, !query.isEmpty {
                title = (running ? "Searching “" : "Searched “") + compact(query) + "”"
            } else { title = activity.title }
        } else {
            var actions: [String] = []
            if searches > 0 { actions.append("\(searches) \(searches == 1 ? "search" : "searches")") }
            if pages > 0 { actions.append("\(pages) \(pages == 1 ? "page" : "pages")") }
            if finds > 0 { actions.append("\(finds) within-page \(finds == 1 ? "lookup" : "lookups")") }
            title = (running ? "Checking " : "Checked ") + actions.joined(separator: " · ")
        }
        if incomplete && !running { title = "Research partly finished" }
        var detail = sources.isEmpty ? (running ? "Looking for relevant sources" : "Open to see the search details") : "\(sources.count) linked \(sources.count == 1 ? "source" : "sources")"
        if activities.count > 1 {
            if !incomplete || running {
                if let query = queries.first, !query.isEmpty {
                    title = (running ? "Looking up “" : "Looked up “") + compact(query) + "”"
                } else if let page = activities.flatMap(\.sources).first {
                    title = (running ? "Reading “" : "Read “") + compact(page.title) + "”"
                }
            }
            var counts: [String] = []
            if searches > 0 { counts.append("\(searches) \(searches == 1 ? "search" : "searches")") }
            if pages > 0 { counts.append("\(pages) \(pages == 1 ? "page" : "pages")") }
            if finds > 0 { counts.append("\(finds) within-page \(finds == 1 ? "lookup" : "lookups")") }
            if !sources.isEmpty { counts.append("\(sources.count) linked \(sources.count == 1 ? "source" : "sources")") }
            detail = counts.joined(separator: " · ")
        }
        return ActivitySummary(title: title, detail: detail, symbol: "globe", running: running, needsAttention: incomplete)
    }

    public static func tools(_ receipts: [Message], in messages: [Message]) -> ActivitySummary {
        var actions: [String] = [], counts: [String: Int] = [:]
        var attention = 0, pending = 0
        for receipt in receipts {
            let call = messages.reversed().flatMap(\.toolCalls).first { $0.id == receipt.toolCallID }
            let output = (try? JSONValue.parse(receipt.text)) ?? .null
            if output["status"] == .string("pending") { pending += 1; continue }
            if receipt.toolFailureDescription != nil || ["outcome_unknown", "interrupted", "failed"].contains(output["status"]?.stringValue ?? "") { attention += 1; continue }
            let title = receiptTitle(call: call, output: output)
            if counts[title] == nil { actions.append(title) }
            counts[title, default: 0] += 1
        }
        actions = actions.map { title in
            let count = counts[title] ?? 1
            guard count > 1 else { return title }
            switch title {
            case "Read an earlier chat": return "Read \(count) earlier chats"
            case "Read the document": return "Read \(count) documents"
            case "Ran a calculation": return "Ran \(count) calculations"
            case "Created a file": return "Created \(count) files"
            default: return title
            }
        }
        let title = actions.isEmpty ? (pending > 0 ? "Waiting for input or iPhone" : "Work needs attention") : actions.prefix(2).joined(separator: " · ")
        var details = ["\(receipts.count) \(receipts.count == 1 ? "step" : "steps")"]
        if attention > 0 { details.append("\(attention) needs attention") }
        else if pending > 0 { details.append("\(pending) pending") }
        else if actions.count > 2 { details.append("\(actions.count - 2) more actions") }
        else if receipts.count == 1, let receipt = receipts.first,
                let call = messages.reversed().flatMap(\.toolCalls).first(where: { $0.id == receipt.toolCallID }),
                let argument = ToolResultPresentation.arguments(of: call),
                let context = ["query", "filename", "title"].compactMap({ argument[$0]?.stringValue }).first, !context.isEmpty {
            details = [compact(context, limit: 95)]
        }
        return ActivitySummary(title: title, detail: details.joined(separator: " · "), symbol: attention > 0 ? "exclamationmark.circle" : pending > 0 ? "clock" : "checkmark.circle", needsAttention: attention > 0 || pending > 0)
    }

    public static func receiptTitle(call: ToolCall?, output: JSONValue) -> String {
        switch output["status"]?.stringValue {
        case "pending": return "Waiting for input or iPhone"
        case "cancelled": return "Review cancelled"
        case "outcome_unknown": return "Outcome needs checking"
        case "interrupted": return "Review paused"
        case "failed": return "Action could not finish"
        default: break
        }
        let name = call?.name == "use_tool" ? call?.arguments["name"]?.stringValue ?? "" : call?.name ?? ""
        switch name {
        case "get_capabilities", "find_tools": return "Checked available tools"
        case "get_device_info", "get_app_context": return "Checked current context"
        case "read_memory": return "Checked saved memory"
        case "save_memory": return "Updated saved memory"
        case "forget_memory": return "Removed saved context"
        case "list_conversations": return "Browsed earlier chats"
        case "read_conversation": return "Read an earlier chat"
        case "search_history", "read_history": return "Reviewed this conversation"
        case "search_workspace", "search_context": return "Searched saved context"
        case "read_workspace": return "Read related saved context"
        case "read_inbox": return "Read saved captures"
        case "read_task", "update_plan": return "Reviewed task progress"
        case "read_project": return "Read the project context"
        case "update_project": return "Updated the project context"
        case "run_javascript", "run_python": return "Ran a calculation"
        case "read_capture", "inspect_depth": return "Inspected the saved image"
        case "read_file", "get_file_metadata", "inspect_document": return "Read the document"
        case "search_files", "list_files", "list_workspaces": return "Looked through connected files"
        case "connect_workspace": return "Connected the selected folder"
        case "create_artifact", "create_pdf", "create_file": return "Created a file"
        case "propose_file_edit": return "Prepared document changes"
        case "apply_file_edit", "update_artifact": return "Updated the document"
        case "read_artifact_revision": return "Read the document version"
        case "export_artifact", "share_files": return "Prepared files for sharing"
        case "get_surface_schema", "present_surface", "update_surface": return "Prepared an interactive view"
        case "read_surface": return "Read your current selections"
        case "find_contacts": return "Searched your contacts"
        case "compose_email", "compose_message_with_files", "compose_text_message": return "Reviewed the message draft"
        case "prepare_phone_call": return "Prepared the call"
        case "prepare_route", "read_route", "open_in_maps": return "Prepared directions"
        case "get_current_location": return "Read your approved location"
        case "request_input": return output["status"] == .string("skipped") ? "Question skipped" : "Received your answer"
        case "list_planning_sources", "read_schedule", "find_available_time": return "Checked your schedule"
        case "read_reminders": return "Checked your reminders"
        case "save_calendar_event": return "Saved the reviewed event"
        case "prepare_calendar_event": return "Reviewed the event details"
        case "save_reminder", "complete_reminder": return "Updated the reviewed reminder"
        case "delete_planning_item", "apply_planning_changes": return "Applied reviewed planning changes"
        case "list_health_types": return "Checked connected Health data"
        case "read_health_data", "read_health_overview": return "Read selected Health information"
        case "schedule_assistant_task": return "Prepared scheduled work"
        case "transfer_file_to_computer", "list_task_files": return "Prepared the task files"
        default: return "Checked the action result"
        }
    }
}
