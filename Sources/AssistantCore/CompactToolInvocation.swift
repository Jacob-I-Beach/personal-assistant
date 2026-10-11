import Foundation

/// Small-context models supply named values through guided structure instead of
/// hand-escaping an entire tool call inside a JSON string. Old saved calls still read.
public enum CompactToolInvocation {
    public static let parameters: JSONValue = .object([
        "type": .string("object"), "additionalProperties": .bool(false),
        "required": .array([.string("name"), .string("arguments")]),
        "properties": .object([
            "name": .object(["type": .string("string"), "description": .string("Exact name returned by find_tools.")]),
            "arguments": .object([
                "type": .string("array"), "maxItems": .number(64),
                "description": .string("One entry for each parameter in the discovered schema. Use an empty list for a tool with no parameters."),
                "items": .object([
                    "type": .string("object"), "additionalProperties": .bool(false),
                    "required": .array([.string("name"), .string("value")]),
                    "properties": .object([
                        "name": .object(["type": .string("string"), "description": .string("Parameter name.")]),
                        "value": .object(["type": .string("string"), "description": .string("Parameter value as text, following the discovered schema. Preserve the text exactly.")])
                    ])
                ])
            ])
        ])
    ])

    public static func values(from arguments: JSONValue) throws -> JSONValue {
        if let items = arguments["arguments"]?.arrayValue {
            guard items.count <= 64 else { throw AssistantError.invalidTool("Supply at most 64 named tool parameters.") }
            var values: [String: JSONValue] = [:]
            for item in items {
                guard let object = item.objectValue, Set(object.keys) == ["name", "value"],
                      let name = item["name"]?.stringValue, !name.isEmpty, name.count <= 100,
                      let value = item["value"]?.stringValue, values[name] == nil else {
                    throw AssistantError.invalidTool("Each tool parameter needs a unique name and a text value. Correct the call using the discovered schema.")
                }
                values[name] = .string(value)
            }
            return .object(values)
        }
        if let legacy = arguments["arguments_json"]?.stringValue,
           let decoded = try? JSONValue.parse(legacy), decoded.objectValue != nil { return decoded }
        throw AssistantError.invalidTool("The tool arguments could not be read. Resend them as the named arguments list shown in use_tool; do not ask the user to supply information the tool can obtain.")
    }

    public static func modelArguments(for call: ToolCall) -> JSONValue {
        guard call.name == "use_tool", call.arguments["arguments"] == nil,
              let name = call.arguments["name"]?.stringValue,
              let values = try? values(from: call.arguments).objectValue,
              values.values.allSatisfy({ $0.stringValue != nil }) else { return call.arguments }
        return .object(["name": .string(name), "arguments": .array(values.keys.sorted().map { .object(["name": .string($0), "value": values[$0]!]) })])
    }
}
