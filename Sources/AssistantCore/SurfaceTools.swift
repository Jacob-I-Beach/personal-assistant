import Foundation

public enum SurfaceTools {
    private static func definition(_ name: String, _ description: String, _ fields: [String: String]) -> ToolDefinition {
        .init(name: name, description: description, parameters: .object(["type": .string("object"), "properties": .object(fields.mapValues { .object(["type": .string("string"), "description": .string($0)]) }), "required": .array(fields.keys.sorted().map(JSONValue.string)), "additionalProperties": .bool(false)]))
    }
    public static let definitions = [
        definition("get_surface_schema", "Get the exact format for native in-chat charts, metrics, tables, comparisons, checklists, timelines or parameter scenarios. These are persistent working objects, not arbitrary HTML or code.", ["kind": "metrics, chart, table, comparison, checklist, timeline, scenario, or all"]),
        definition("present_surface", "Create a validated native working surface in this conversation. Use get_surface_schema first. For calculated metrics/charts/tables pass a successful run_javascript call ID so displayed data comes from that exact result. User interaction is saved locally; it does not send a message or execute device actions.", ["spec_json": "JSON specification matching the chosen kind.", "data_call_id": "Successful JavaScript call ID to supply the data array, or empty for source/model-supplied data and declarative scenarios."]),
        definition("read_surface", "Read the latest selections/parameters and displayed data of a working surface in this conversation. The timestamp and revision distinguish user changes from the originally proposed state.", ["surface_id": "UUID returned by present_surface"]),
        definition("update_surface", "Revise a working surface in place using its current revision from read_surface. Preserves its ID, compatible selections and revision history. Stale updates are rejected. Calculated values need a successful calculation receipt, as when creating a surface.", ["surface_id": "Existing surface UUID", "expected_revision": "Exact revision returned by read_surface", "spec_json": "Full revised surface specification", "data_call_id": "Successful run_javascript or run_python call ID, or empty for source-supplied data"]),
    ]
    public static func schema(_ kind: String) throws -> JSONValue {
        guard kind == "all" || SurfaceKind(rawValue: kind) != nil else { throw AssistantError.invalidTool("Choose a supported surface kind.") }
        let schemas: [String: String] = [
            "metrics": "data: [{label: string, value: number|string, unit?: string, detail?: string}]",
            "chart": "style: bar|line|area (optional, default bar); data: [{label: string, value: finite number, series?: string}]",
            "table": "columns: 1–8 distinct strings; data: arrays of scalar cells matching the columns",
            "comparison": "data: [{id: distinct string, label: string, detail?: string}]. The user can pin one option; pinning is not approval of an external action.",
            "checklist": "data: [{id: distinct string, label: string, detail?: string, checked?: boolean}]. Checkmarks are user tracking, not proof of execution.",
            "timeline": "data: [{label: string, detail?: string, status?: pending|in_progress|completed}]. State supplied by the model must reflect known evidence.",
            "scenario": "inputs: 1–6 {id, label, value, min, max, step}; expression: a number, {input: id}, or {op: add|subtract|multiply|divide|power|min|max, args: [expressions]}. result_label and unit are optional. Math is computed locally from these declared assumptions; no scripts or native actions. Example expression: {op: multiply, args: [{input: price}, {input: count}]}.",
        ]
        return .object(["common": .string("Object with kind, title (1–120 characters), optional subtitle. At most 40 KB and 200 data rows. Unknown fields, nested data cells, HTML, URLs and executable scripts are unsupported. Pass data_call_id to replace data with an actual JavaScript result array; a numeric result is also accepted for metrics. A scenario uses no data array."), "kinds": .object(schemas.filter { kind == "all" || $0.key == kind }.mapValues(JSONValue.string))])
    }
    public static func execute(_ call: ToolCall, store: LocalStore, conversationID: UUID, remote: Bool, localOnly: Bool, health: Bool) async throws -> ToolResult {
        let output: JSONValue
        var localOnly = localOnly, health = health
        switch call.name {
        case "get_surface_schema": output = try schema(call.arguments["kind"]!.stringValue!)
        case "present_surface", "update_surface":
            let existing = try await store.surfaces(conversationID: conversationID, remote: remote)
            if call.name == "present_surface", let original = existing.first(where: { $0.sourceCallID == call.id }) {
                return ToolResult(callID: call.id, name: call.name, succeeded: true, output: .object(["surface_id": .string(original.id.uuidString), "title": .string(original.title), "status": .string("displayed")]))
            }
            let raw = call.arguments["spec_json"]!.stringValue!
            guard raw.utf8.count <= 40_000, var spec = try JSONValue.parse(raw).objectValue else { throw AssistantError.invalidTool("Supply a surface JSON object up to 40 KB.") }
            let sourceID = call.arguments["data_call_id"]!.stringValue!
            if !sourceID.isEmpty {
                let conversation = try await store.loadConversation(conversationID)
                guard let source = conversation.messages.first(where: { $0.role == .tool && $0.toolCallID == sourceID && $0.state == .complete }),
                      !remote || !source.containsLocalOnlyContext,
                      let sourceCall = conversation.messages.flatMap(\.toolCalls).first(where: { $0.id == sourceID }),
                      ["run_javascript", "run_python"].contains(sourceCall.name) || (sourceCall.name == "use_tool" && ["run_javascript", "run_python"].contains(sourceCall.arguments["name"]?.stringValue ?? "")),
                      let receipt = try? JSONValue.parse(source.text), receipt["tool_succeeded"] == .bool(true), let data = receipt["result"] else {
                    throw AssistantError.invalidTool("Use a successful JavaScript result from this conversation for surface data.")
                }
                if let number = data.numberValue, spec["kind"] == .string("metrics") { spec["data"] = .array([.object(["label": spec["result_label"] ?? .string("Result"), "value": .number(number)])]) }
                else { spec["data"] = data }
                localOnly = localOnly || source.containsLocalOnlyContext; health = health || source.containsHealthData
            }
            var surface = try WorkSurface(conversationID: conversationID, sourceCallID: call.id, spec: .object(spec), localOnly: localOnly, health: health, dataCallID: sourceID.isEmpty ? nil : sourceID)
            if call.name == "update_surface" {
                guard let id = call.arguments["surface_id"]?.stringValue.flatMap(UUID.init(uuidString:)), let revision = Int(call.arguments["expected_revision"]?.stringValue ?? "") else { throw AssistantError.invalidTool("Read the surface and supply its current revision.") }
                surface = try await store.reviseSurface(id: id, conversationID: conversationID, expectedRevision: revision, replacement: surface)
            } else { try await store.saveSurface(surface) }
            output = .object(["surface_id": .string(surface.id.uuidString), "title": .string(surface.title), "revision": .number(Double(surface.revision)), "kind": .string(surface.kind.rawValue), "status": .string("displayed"), "data_source": .string(sourceID.isEmpty ? "Supplied data and declared assumptions; not independently verified" : "Exact saved calculation result"), "interaction": .string("Selections stay in this object. Ask about these changes explicitly sends a follow-up; read_surface returns the current revision.")])
        case "read_surface":
            guard let id = UUID(uuidString: call.arguments["surface_id"]!.stringValue!),
                  let surface = try await store.surfaces(conversationID: conversationID, remote: remote).first(where: { $0.id == id }) else { throw AssistantError.invalidTool("This surface is not available in the current conversation.") }
            localOnly = localOnly || surface.containsLocalOnlyContext; health = health || surface.containsHealthData
            output = .object(["state": try surface.summary(), "spec": surface.spec])
        default: throw AssistantError.invalidTool("Unknown surface tool.")
        }
        var result = ToolResult(callID: call.id, name: call.name, succeeded: true, output: output)
        result.containsLocalOnlyContext = localOnly; result.containsHealthData = health
        return result
    }
}
