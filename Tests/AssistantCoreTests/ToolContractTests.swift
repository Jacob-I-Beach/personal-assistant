import XCTest
@testable import AssistantCore

final class ToolContractTests: XCTestCase, @unchecked Sendable {
    func testStructuredCompactInvocationExecutesWithoutNestedJSONEscaping() async throws {
        let store = try makeTestStore(), chat = Conversation()
        try await store.save(chat)
        let tools = AssistantTools(store: store, conversationID: chat.id, captureIDs: [], sandbox: JavaScriptSandbox(), compactCatalog: true)
        let arguments: JSONValue = .object(["name": .string("run_javascript"), "arguments": .array([
            .object(["name": .string("code"), "value": .string("return {total: 18.5 + 27.25 + 14.75, note: 'quoted \\\"text\\\"'};")]),
            .object(["name": .string("input_json"), "value": .string("null")])
        ])])
        let result = try await tools.execute(ToolCall(id: "structured", name: "use_tool", arguments: arguments))
        XCTAssertTrue(result.succeeded); XCTAssertEqual(result.output["result"]?["total"], .number(60.5))
        XCTAssertEqual(result.callID, "structured")
        let capabilities = try await tools.execute(ToolCall(id: "caps", name: "get_capabilities", arguments: .object([:])))
        XCTAssertTrue(capabilities.output["callable_entry_points"]?.arrayValue?.contains(.string("find_tools")) == true)
        let repeated: JSONValue = .object(["arguments": .array([
            .object(["name": .string("query"), "value": .string("first")]),
            .object(["name": .string("query"), "value": .string("second")])
        ])])
        XCTAssertThrowsError(try CompactToolInvocation.values(from: repeated))
    }
    func testTypedContractsNormalizeOnlyDeclaredFieldsAndKeepPermissionValuesExplicit() throws {
        let schema: JSONValue = .object(["type": .string("object"), "additionalProperties": .bool(false), "required": .array([.string("limit"), .string("include_completed"), .string("until")]), "properties": .object([
            "limit": .object(["type": .string("integer"), "minimum": .number(1), "maximum": .number(20)]),
            "include_completed": .object(["type": .string("boolean")]),
            "until": .object(["type": .array([.string("string"), .string("null")])])
        ])])
        let result = try ToolArguments.normalize(.object(["limit": .string("4"), "include_completed": .string("false")]), schema: schema)
        XCTAssertEqual(result["limit"], .number(4)); XCTAssertEqual(result["include_completed"], .bool(false)); XCTAssertEqual(result["until"], .null)
        XCTAssertThrowsError(try ToolArguments.normalize(.object(["limit": .number(4.5), "include_completed": .bool(false)]), schema: schema))
        XCTAssertThrowsError(try ToolArguments.normalize(.object(["limit": .number(4), "include_completed": .bool(false), "unreviewed_send": .bool(true)]), schema: schema))
    }
}
