import Foundation

/// The canonical contract is typed. Compact/local callers and saved v1 calls may
/// supply text scalars; conversion follows the declared schema, never a guess.
public enum ToolArguments {
    /// The exact integer domain shared by Swift and JavaScript tool contracts.
    public static func integer(_ value: JSONValue?, default fallback: Int = 0, field: String = "argument") throws -> Int {
        guard let value else { return fallback }
        guard let number = value.numberValue, number.isFinite, abs(number) <= 9_007_199_254_740_991,
              let result = Int(exactly: number) else { throw AssistantError.invalidTool("\(field) needs a supported whole number.") }
        return result
    }
    public static func normalize(_ input: JSONValue, schema: JSONValue, path: String = "arguments", depth: Int = 0) throws -> JSONValue {
        guard depth < 20 else { throw AssistantError.invalidTool("The tool arguments are too deeply nested.") }
        var value = input
        let types = schema["type"]?.arrayValue?.compactMap(\.stringValue) ?? schema["type"]?.stringValue.map { [$0] } ?? []
        if types.contains("null"), value == .null || value == .string("") || value == .string("null") { return .null }
        if let choices = schema["anyOf"]?.arrayValue {
            for choice in choices {
                if let match = try? normalize(value, schema: choice, path: path, depth: depth + 1) { return match }
            }
            throw AssistantError.invalidTool("\(path) does not match the tool's accepted formats.")
        }
        let kind = types.first(where: { $0 != "null" })
        if let text = value.stringValue, kind != "string" {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if kind == "boolean", ["true", "false"].contains(trimmed.lowercased()) { value = .bool(trimmed.lowercased() == "true") }
            else if kind == "integer" || kind == "number", trimmed.range(of: #"^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil, let number = Double(trimmed), number.isFinite { value = .number(number) }
            else if kind == "object" || kind == "array", let decoded = try? JSONValue.parse(text) { value = decoded }
        }
        switch kind {
        case "object":
            guard var object = value.objectValue else { throw AssistantError.invalidTool("\(path) needs named fields.") }
            let properties = schema["properties"]?.objectValue ?? [:]
            let required = Set(schema["required"]?.arrayValue?.compactMap(\.stringValue) ?? [])
            if schema["additionalProperties"] == .bool(false), !Set(object.keys).isSubset(of: Set(properties.keys)) {
                throw AssistantError.invalidTool("\(path) contains a field the tool does not accept.")
            }
            for (key, definition) in properties {
                if let supplied = object[key] { object[key] = try normalize(supplied, schema: definition, path: key, depth: depth + 1) }
                else if required.contains(key) {
                    if definition["type"]?.arrayValue?.contains(.string("null")) == true { object[key] = .null }
                    else { throw AssistantError.invalidTool("The tool needs the \(key) field.") }
                }
            }
            value = .object(object)
        case "array":
            guard let items = value.arrayValue, let itemSchema = schema["items"] else { throw AssistantError.invalidTool("\(path) needs a list.") }
            if let maximum = schema["maxItems"]?.numberValue, Double(items.count) > maximum { throw AssistantError.invalidTool("\(path) contains too many items.") }
            if let minimum = schema["minItems"]?.numberValue, Double(items.count) < minimum { throw AssistantError.invalidTool("\(path) needs more items.") }
            value = .array(try items.map { try normalize($0, schema: itemSchema, path: path, depth: depth + 1) })
        case "number", "integer":
            guard let number = value.numberValue, number.isFinite, kind != "integer" || number.rounded() == number else { throw AssistantError.invalidTool("\(path) needs \(kind == "integer" ? "a whole number" : "a number").") }
            if kind == "integer" { _ = try integer(value, field: path) }
            if let minimum = schema["minimum"]?.numberValue, number < minimum { throw AssistantError.invalidTool("\(path) is below the supported minimum.") }
            if let maximum = schema["maximum"]?.numberValue, number > maximum { throw AssistantError.invalidTool("\(path) exceeds the supported maximum.") }
        case "boolean":
            guard case .bool = value else { throw AssistantError.invalidTool("\(path) needs true or false.") }
        case "string":
            guard let text = value.stringValue else { throw AssistantError.invalidTool("\(path) needs text.") }
            if let maximum = schema["maxLength"]?.numberValue, Double(text.unicodeScalars.count) > maximum { throw AssistantError.invalidTool("\(path) is too long.") }
        case "null":
            guard value == .null else { throw AssistantError.invalidTool("\(path) must be omitted.") }
        default: throw AssistantError.invalidTool("The tool has an unsupported parameter schema.")
        }
        if let choices = schema["enum"]?.arrayValue, !choices.contains(value) { throw AssistantError.invalidTool("\(path) is not one of the supported choices.") }
        return value
    }
}
