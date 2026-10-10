import AssistantCore
import SwiftUI

struct WorkReceiptView: View {
    @EnvironmentObject private var model: AppModel
    let message: Message
    private var call: ToolCall? { model.conversation.messages.flatMap(\.toolCalls).first { $0.id == message.toolCallID } }
    private var toolName: String { call?.name == "use_tool" ? call?.arguments["name"]?.stringValue ?? "use_tool" : call?.name ?? "tool" }
    private var output: JSONValue? { try? JSONValue.parse(message.text) }
    private var title: String {
        if message.toolFailureDescription != nil { return "Action needs attention" }
        switch toolName {
        case "run_javascript": return "Ran JavaScript on this iPhone"
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
                VStack(alignment: .leading, spacing: 10) {
                    if let call {
                        Text("Request").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        Text(call.arguments["code"]?.stringValue ?? call.arguments["arguments_json"]?.stringValue ?? (try? call.arguments.jsonString()) ?? "")
                            .font(.caption.monospaced()).textSelection(.enabled)
                    }
                    Text("Result").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Text(message.text).font(.caption.monospaced()).textSelection(.enabled)
                }.padding(.top, 6)
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Label(title, systemImage: message.toolFailureDescription == nil ? "checkmark.circle" : "exclamationmark.circle")
                        .font(.footnote.weight(.medium)).foregroundStyle(message.toolFailureDescription == nil ? Color.secondary : Color.red)
                    if let failure = message.toolFailureDescription { Text(failure).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                    else if let filename = output?["filename"]?.stringValue { Text(filename).font(.caption).foregroundStyle(.secondary) }
                    else if toolName == "run_javascript", let value = output?["result"], let text = try? value.jsonString() { Text(String(text.prefix(160))).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(3) }
                }
            }
        }
    }
}
