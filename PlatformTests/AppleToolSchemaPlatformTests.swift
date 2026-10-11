import AssistantCore
import FoundationModels
import XCTest
@testable import PersonalAssistant

final class AppleToolSchemaPlatformTests: XCTestCase {
    func testCompactToolSchemaKeepsAnArrayOfNamedArguments() throws {
        let schema = try AppleToolSchema.make(ToolDefinition(name: "use_tool", description: "Synthetic invocation", parameters: CompactToolInvocation.parameters))
        let value = try JSONValue.parse(String(decoding: JSONEncoder().encode(schema), as: UTF8.self))
        func types(_ value: JSONValue) -> Set<String> {
            if let object = value.objectValue {
                return Set(object["type"]?.stringValue.map { [$0] } ?? []).union(object.values.reduce(into: Set<String>()) { $0.formUnion(types($1)) })
            }
            return (value.arrayValue ?? []).reduce(into: Set<String>()) { $0.formUnion(types($1)) }
        }
        XCTAssertTrue(types(value).contains("array"), "Named arguments must not be flattened into a string by the Apple adapter.")
        XCTAssertTrue(types(value).contains("object"))
        let content = try GeneratedContent(json: #"{"name":"get_current_location","arguments":[{"name":"reason","value":"Find the closest requested place"}]}"#)
        let decoded = try CompactToolInvocation.values(from: JSONValue.parse(content.jsonString))
        XCTAssertEqual(decoded["reason"], .string("Find the closest requested place"))
    }
}
