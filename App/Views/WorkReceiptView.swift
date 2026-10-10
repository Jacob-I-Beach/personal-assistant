import AssistantCore
import SwiftUI

struct WorkReceiptView: View {
    @EnvironmentObject private var model: AppModel
    let message: Message
    private var call: ToolCall? { model.conversation.messages.flatMap(\.toolCalls).first { $0.id == message.toolCallID } }
    private var toolName: String { call?.name == "use_tool" ? call?.arguments["name"]?.stringValue ?? "use_tool" : call?.name ?? "tool" }
    private var output: JSONValue? { try? JSONValue.parse(message.text) }
    private var arguments: JSONValue? { ToolResultPresentation.arguments(of: call) }
    private var resultFields: [ToolResultPresentation.Field] {
        guard let value = output?["result"] else { return [] }
        return ToolResultPresentation.fields(value)
    }
    private var title: String {
        if output?["status"]?.stringValue == "cancelled" { return "Action cancelled" }
        if message.toolFailureDescription != nil { return "Action needs attention" }
        switch toolName {
        case "get_capabilities": return "Checked available tools"
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
        case "get_current_location": return "Read your approved location"
        case "prepare_calendar_event": return "Saved your reviewed event"
        case "compose_text_message": return "Completed message review"
        case "prepare_phone_call", "open_in_maps": return "Opened the approved action"
        case "find_tools": return "Found available tools"
        case "read_memory": return "Read saved memory"
        default: return toolName.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
    var body: some View {
        if toolName == "update_plan", let steps = output?["steps"]?.arrayValue, message.toolFailureDescription == nil {
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
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 14) {
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
                        Text("Values are rounded for display. Exact values are available in Technical details.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if let code = arguments?["code"]?.stringValue {
                        DisclosureGroup("Code") {
                            ScrollView(.horizontal) { Text(code).font(.caption.monospaced()).textSelection(.enabled).padding(.vertical, 8) }
                            Button("Copy code", systemImage: "doc.on.doc") { UIPasteboard.general.string = code }.font(.caption)
                        }.font(.footnote)
                    }
                    DisclosureGroup("Technical details") {
                        VStack(alignment: .leading, spacing: 8) {
                            if let call {
                                Text("Request").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                                Text((try? call.arguments.jsonString()) ?? "").font(.caption.monospaced()).textSelection(.enabled)
                            }
                            Text("Exact result").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                            Text(message.text).font(.caption.monospaced()).textSelection(.enabled)
                        }.padding(.top, 8)
                    }.font(.footnote)
                }.padding(.top, 12)
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Label(title, systemImage: message.toolFailureDescription == nil ? "checkmark.circle" : "exclamationmark.circle")
                        .font(.footnote.weight(.medium)).foregroundStyle(message.toolFailureDescription == nil || output?["status"]?.stringValue == "cancelled" ? Color.secondary : Color.red)
                    if output?["status"]?.stringValue == "cancelled" { Text("No completed action was reported.").font(.caption).foregroundStyle(.secondary) }
                    else if let failure = message.toolFailureDescription { Text(failure).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                    else if let filename = output?["filename"]?.stringValue { Text(filename).font(.caption).foregroundStyle(.secondary) }
                    else if toolName == "run_javascript" {
                        Text(resultFields.count == 1 ? (resultFields.first?.value ?? "Completed") : "\(resultFields.count) calculated values")
                            .font(.subheadline).foregroundStyle(.primary).lineLimit(2)
                        Text("On this iPhone").font(.caption).foregroundStyle(.secondary)
                    } else if let matches = output?["matches"]?.arrayValue {
                        Text("\(matches.count) matches").font(.caption).foregroundStyle(.secondary)
                    } else if toolName == "find_tools", let tools = output?["tools"]?.arrayValue {
                        Text("\(tools.count) available tools").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .tint(.secondary)
            .padding(14).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
            .accessibilityIdentifier("tool-receipt")
        }
    }
}
