import AssistantCore
import FoundationModels

/// Preserve tool argument types for Apple's guided generation. Converting every
/// property into text breaks structured invocation, booleans and numeric tools.
enum AppleToolSchema {
    static func make(_ definition: ToolDefinition) throws -> GenerationSchema {
        try GenerationSchema(root: schema(definition.parameters, name: definition.name + "Arguments", depth: 0), dependencies: [])
    }
    private static func schema(_ value: JSONValue, name: String, depth: Int) throws -> DynamicGenerationSchema {
        guard depth < 16 else { throw AssistantError.invalidTool("The tool schema is too deeply nested.") }
        if let variants = value["anyOf"]?.arrayValue {
            return DynamicGenerationSchema(name: name, anyOf: try variants.enumerated().map { try schema($0.element, name: name + "Variant" + String($0.offset), depth: depth + 1) })
        }
        if let types = value["type"]?.arrayValue?.compactMap(\.stringValue) {
            return DynamicGenerationSchema(name: name, anyOf: try types.map { try schema(.object(["type": .string($0)]), name: name + $0, depth: depth + 1) })
        }
        switch value["type"]?.stringValue {
        case "string":
            let choices = value["enum"]?.arrayValue?.compactMap(\.stringValue) ?? []
            return DynamicGenerationSchema(type: String.self, guides: choices.isEmpty ? [] : [.anyOf(choices)])
        case "integer": return DynamicGenerationSchema(type: Int.self)
        case "number": return DynamicGenerationSchema(type: Double.self)
        case "boolean": return DynamicGenerationSchema(type: Bool.self)
        case "null": return .null
        case "array":
            guard let items = value["items"] else { throw AssistantError.invalidTool("An array tool parameter needs an item schema.") }
            return DynamicGenerationSchema(arrayOf: try schema(items, name: name + "Item", depth: depth + 1),
                                           minimumElements: value["minItems"]?.numberValue.map(Int.init), maximumElements: value["maxItems"]?.numberValue.map(Int.init))
        case "object":
            let required = Set(value["required"]?.arrayValue?.compactMap(\.stringValue) ?? [])
            return DynamicGenerationSchema(name: name, properties: try (value["properties"]?.objectValue ?? [:]).sorted { $0.key < $1.key }.map {
                DynamicGenerationSchema.Property(name: $0.key, description: $0.value["description"]?.stringValue,
                                                  schema: try schema($0.value, name: name + "_" + $0.key, depth: depth + 1), isOptional: !required.contains($0.key))
            })
        default: throw AssistantError.invalidTool("This tool parameter has no supported type.")
        }
    }
}
