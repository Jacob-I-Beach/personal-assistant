import AssistantCore
import SwiftUI

struct WorkReceiptView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var navigation: ChatNavigation
    let message: Message
    @State private var memoryUndoNotice: String?
    private var call: ToolCall? {
        guard let index = model.conversation.messages.firstIndex(where: { $0.id == message.id }) else { return nil }
        return model.conversation.messages.prefix(index).reversed().flatMap(\.toolCalls).first { $0.id == message.toolCallID }
    }
    private var toolName: String { call?.name == "use_tool" ? call?.arguments["name"]?.stringValue ?? "use_tool" : call?.name ?? "tool" }
    private var output: JSONValue? { try? JSONValue.parse(message.text) }
    private var arguments: JSONValue? { ToolResultPresentation.arguments(of: call) }
    private var depthInspection: DepthInspection? {
        guard let data = message.text.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(DepthInspection.self, from: data)
    }
    private var resultFields: [ToolResultPresentation.Field] {
        guard let value = output?["result"] else { return [] }
        return ToolResultPresentation.fields(value)
    }
    private var title: String {
        if output?["status"]?.stringValue == "cancelled" { return "Action cancelled" }
        if output?["status"]?.stringValue == "outcome_unknown" { return "Outcome not confirmed" }
        if output?["status"]?.stringValue == "interrupted" { return "Review interrupted" }
        if output?["status"]?.stringValue == "failed" { return "Action could not finish" }
        if message.toolFailureDescription != nil { return "Action needs attention" }
        switch toolName {
        case "get_capabilities": return "Checked available tools"
        case "get_surface_schema": return "Prepared an interactive view"
        case "read_surface": return "Read the current selections"
        case "inspect_depth": return "Inspected saved depth"
        case "connect_workspace": return "Connected a folder"
        case "list_workspaces", "list_files": return "Browsed connected folders"
        case "read_file", "get_file_metadata": return "Read a connected file"
        case "search_files": return "Searched a connected folder"
        case "create_file": return "Saved a file in your folder"
        case "propose_file_edit": return "Prepared file changes"
        case "apply_file_edit": return "Applied reviewed file changes"
        case "export_artifact": return "Exported to Files"
        case "run_javascript": return "Calculated with JavaScript"
        case "create_artifact": return "Created a file"
        case "create_pdf": return "Created a PDF"
        case "search_history": return "Searched this conversation"
        case "search_workspace": return "Searched your workspace"
        case "read_history", "read_workspace": return "Read saved context"
        case "read_capture": return "Read image observations"
        case "get_device_info": return "Checked device resources"
        case "get_app_context": return "Checked current app context"
        case "get_current_location": return "Read your approved location"
        case "prepare_calendar_event": return "Saved your reviewed event"
        case "compose_text_message": return "Completed message review"
        case "prepare_phone_call", "open_in_maps": return "Opened the approved action"
        case "find_tools": return "Found available tools"
        case "read_memory": return "Read saved memory"
        case "save_memory": return output?["change"]?.stringValue == "updated" ? "Updated saved memory" : "Remembered useful context"
        case "forget_memory": return "Forgot saved context"
        case "list_conversations": return "Browsed recent chats"
        case "read_conversation": return "Read an earlier conversation"
        case "read_task": return "Checked saved progress"
        case "list_health_types": return "Checked connected Health data"
        case "read_health_data", "read_health_overview": return "Read relevant Health data"
        case "read_inbox": return "Read saved captures"
        case "request_input": return output?["status"] == .string("skipped") ? "Question skipped" : "Received your answer"
        case "list_planning_sources": return "Checked planning connections"
        case "read_schedule": return "Read your selected calendars"
        case "find_available_time": return "Checked available time"
        case "read_reminders": return "Read your selected reminders"
        case "save_calendar_event": return "Saved and checked your event"
        case "save_reminder": return "Saved and checked your reminder"
        case "complete_reminder": return "Completed your reminder"
        case "prepare_route": return "Prepared directions"
        case "read_route": return "Read the saved route"
        default: return toolName.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
    var body: some View {
        if toolName == "request_input", let question = output?["question"]?.stringValue ?? arguments?["question"]?.stringValue, message.toolFailureDescription == nil {
            VStack(alignment: .leading, spacing: 8) {
                Label("Question", systemImage: "bubble.left").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Text(question).font(.body).textSelection(.enabled)
                if output?["status"] == .string("skipped") { Text("You skipped this question.").font(.caption).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
        } else if toolName == "prepare_route", let raw = output?["route_id"]?.stringValue, let id = UUID(uuidString: raw), message.toolFailureDescription == nil {
            RouteCard(id: id)
        } else if toolName == "present_surface", let raw = output?["surface_id"]?.stringValue, let id = UUID(uuidString: raw), message.toolFailureDescription == nil {
            WorkingSurfaceView(id: id)
        } else if toolName == "update_plan", let steps = output?["steps"]?.arrayValue, message.toolFailureDescription == nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("Work plan").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: step["status"]?.stringValue == "completed" ? "checkmark.circle.fill" : step["status"]?.stringValue == "in_progress" ? "circle.inset.filled" : "circle")
                            .foregroundStyle(.secondary)
                        Text(step["title"]?.stringValue ?? "").font(.subheadline)
                    }
                }
            }.padding(.vertical, 6)
        } else {
            AssistantDisclosure(nested: true) {
                VStack(alignment: .leading, spacing: 14) {
                    if let output {
                        ForEach(ToolResultPresentation.summary(tool: toolName, output: output)) { field in
                            VStack(alignment: .leading, spacing: 3) { Text(field.label).font(.caption).foregroundStyle(.secondary); Text(field.value).font(.subheadline) }
                        }
                    }
                    if message.toolFailureDescription == nil,
                       let raw = output?["artifact_id"]?.stringValue, let id = UUID(uuidString: raw),
                       let artifact = model.artifacts.first(where: { $0.id == id && $0.conversationID == model.conversation.id && !model.conversation.excludedArtifactIDs.contains(id) }) {
                        Button { navigation.destination = .artifact(id) } label: { Label("Open " + artifact.filename, systemImage: "doc.text") }
                    }
                    if message.toolFailureDescription == nil,
                       let raw = output?["file_id"]?.stringValue, let id = UUID(uuidString: raw),
                       let file = model.files.first(where: { $0.id == id && !model.conversation.excludedFileIDs.contains(id) }) {
                        Button { navigation.destination = .file(id) } label: { Label("Open " + file.filename, systemImage: file.icon) }
                    }
                    if ["save_memory", "forget_memory"].contains(toolName), let raw = output?["memory_change_id"]?.stringValue, let id = UUID(uuidString: raw), message.toolFailureDescription == nil {
                        if let title = output?["title"]?.stringValue { Text(title).font(.subheadline) }
                        Button("Undo memory change", systemImage: "arrow.uturn.backward") {
                            Task {
                                do { _ = try await model.store?.undoMemoryChange(id); memoryUndoNotice = "Change undone. Future replies use the restored memory state." }
                                catch { memoryUndoNotice = error.localizedDescription }
                            }
                        }.font(.footnote).disabled(memoryUndoNotice != nil)
                        if let memoryUndoNotice { Text(memoryUndoNotice).font(.caption).foregroundStyle(.secondary) }
                    }
                    if toolName == "read_capture", message.toolFailureDescription == nil {
                        if let source = output?["source"]?.stringValue { LabeledContent("Source", value: source).font(.subheadline) }
                        if let meters = output?["center_depth"]?["medianMeters"]?.numberValue {
                            LabeledContent("Depth near the center", value: "\(meters.formatted(.number.precision(.fractionLength(2)))) m").font(.subheadline)
                            Text("Saved at capture time; this is not the size of an object.").font(.caption).foregroundStyle(.secondary)
                        }
                        if let text = output?["recognized_text"]?.arrayValue {
                            Text(text.isEmpty ? "No readable text was detected." : "\(text.count) text regions detected.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if toolName == "inspect_depth", let inspection = depthInspection { DepthInspectionView(inspection: inspection) }
                    if toolName == "run_javascript", message.toolFailureDescription == nil {
                        ForEach(resultFields) { field in
                            ViewThatFits(in: .horizontal) {
                                HStack(alignment: .firstTextBaseline, spacing: 20) {
                                    Text(field.label).foregroundStyle(.secondary)
                                    Spacer(minLength: 0)
                                    Text(field.value).multilineTextAlignment(.trailing).monospacedDigit()
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(field.label).foregroundStyle(.secondary)
                                    Text(field.value).monospacedDigit()
                                }
                            }.font(.subheadline).textSelection(.enabled)
                        }
                        ForEach(Array((output?["artifacts"]?.arrayValue ?? []).enumerated()), id: \.offset) { _, artifact in
                            if let filename = artifact["filename"]?.stringValue {
                                Label(filename, systemImage: "doc").font(.subheadline)
                            }
                        }
                        Text("Values are rounded for display. Exact values are retained in the diagnostic record.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if let code = arguments?["code"]?.stringValue {
                        AssistantDisclosure(nested: true) {
                            ScrollView(.horizontal) { Text(code).font(.caption.monospaced()).textSelection(.enabled).padding(.vertical, 8) }
                            Button("Copy code", systemImage: "doc.on.doc") { UIPasteboard.general.string = code }.font(.caption)
                        } label: { Label("Code", systemImage: "curlybraces") }.font(.footnote)
                    }
                    if let arguments, !ReceiptDetails.nodes(arguments).isEmpty {
                        AssistantDisclosure(nested: true) {
                            ReceiptDetailView(nodes: ReceiptDetails.nodes(arguments)).padding(.top, 10)
                        } label: { Label("What was requested", systemImage: "text.magnifyingglass") }.font(.footnote)
                    }
                    if let output {
                        ReceiptDetailView(nodes: ReceiptDetails.readableContent(output))
                    } else { Text(message.text).font(.subheadline).textSelection(.enabled) }
                    HStack(spacing: 12) {
                        Label(message.createdAt.formatted(date: .omitted, time: .shortened), systemImage: "clock").font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        MessageActionButton(title: "Copy diagnostic record", icon: "doc.on.doc", confirmation: "Copied") {
                            UIPasteboard.general.string = "Tool: \(toolName)\nRequest: \((try? arguments?.jsonString()) ?? "")\nResult: \(message.text)"
                        }
                    }
                }.padding(.top, 12)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Label(title, systemImage: receiptIcon)
                        .font(.caption.weight(.medium)).foregroundStyle(message.toolFailureDescription == nil || output?["status"]?.stringValue == "cancelled" ? Color.secondary : Color.red)
                    if output?["status"]?.stringValue == "cancelled" { Text("No completed action was reported.").font(.caption).foregroundStyle(.secondary) }
                    else if ["outcome_unknown", "interrupted"].contains(output?["status"]?.stringValue ?? "") { Text("Check the outcome before trying this action again.").font(.caption).foregroundStyle(.secondary) }
                    else if let failure = message.toolFailureDescription { Text(failure).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                    else if let filename = output?["filename"]?.stringValue { Text(filename).font(.caption).foregroundStyle(.secondary) }
                }
            }
            .tint(.secondary)
            .font(.caption).padding(.vertical, 3).transaction { $0.animation = nil }
            .accessibilityIdentifier("tool-receipt")
        }
    }
    private var receiptIcon: String {
        switch output?["status"]?.stringValue {
        case "cancelled": "xmark.circle"
        case "outcome_unknown": "questionmark.circle"
        case "interrupted": "pause.circle"
        case "failed": "exclamationmark.circle"
        default: message.toolFailureDescription == nil ? "checkmark.circle" : "exclamationmark.circle"
        }
    }
}
