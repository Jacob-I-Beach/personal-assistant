import Foundation
import XCTest
@testable import AssistantCore

final class WorkspaceUpgradeTests: XCTestCase, @unchecked Sendable {
    func testFileToolArgumentsCanExceedTheOldLimitButRemainBounded() throws {
        func terminal(_ count: Int) throws -> ServerSentEvent {
            let arguments = try JSONValue.object(["content": .string(String(repeating: "x", count: count))]).jsonString()
            let value: JSONValue = .object(["type": .string("response.completed"), "response": .object(["output": .array([
                .object(["type": .string("function_call"), "status": .string("completed"), "call_id": .string("file"), "name": .string("create_file"), "arguments": .string(arguments)])
            ])])])
            return ServerSentEvent(event: nil, data: try value.jsonString())
        }
        var valid = ModelWireDecoder(wireProtocol: .responses)
        let events = try valid.consume(terminal(48_000))
        XCTAssertTrue(events.contains { if case .toolCall = $0 { true } else { false } })
        var large = ModelWireDecoder(wireProtocol: .responses)
        XCTAssertThrowsError(try large.consume(terminal(513 * 1024)))
        XCTAssertFalse(large.completed)
    }
    func testFailedCalculationCannotCreateOrEditAConnectedFile() async throws {
        let store = try makeTestStore()
        let extra = ["create_file", "propose_file_edit", "apply_file_edit"].map { name in
            ToolDefinition(name: name, description: "Fixture", parameters: .object(["type": .string("object"), "properties": .object([:]), "required": .array([]), "additionalProperties": .bool(false)]))
        }
        let tools = AssistantTools(store: store, conversationID: UUID(), captureIDs: [], sandbox: JavaScriptSandbox(),
                                   additionalDefinitions: extra, additionalExecutor: { _ in throw AssistantError.invalidTool("This executor must never be reached.") })
        let failed = try await tools.execute(.init(id: "bad", name: "run_javascript", arguments: .object(["code": .string("throw new Error('failed calculation');"), "input_json": .string("null")])))
        XCTAssertFalse(failed.succeeded)
        for name in extra.map(\.name) {
            let result = try await tools.execute(.init(id: name, name: name, arguments: .object([:])))
            XCTAssertFalse(result.succeeded)
            XCTAssertTrue(result.output["error"]?.stringValue?.contains("Repair and rerun") == true)
        }
    }
    func testCitationCollapseCountsUniqueSourcesAndKeepsInlineNumbers() throws {
        let same = WebCitation(title: "One", url: "https://example.test/one")!
        let all = [same, same] + (2...4).map { WebCitation(title: "Source \($0)", url: "https://example.test/\($0)")! }
        let grouped = CitationSource.group(all)
        XCTAssertEqual(grouped.count, 4); XCTAssertEqual(grouped[0].numbers, [1, 2])
        XCTAssertEqual(grouped[3].numbers, [5])
        XCTAssertEqual(CitationSource.group(Array(all.prefix(3))).count, 2)
    }
    func testEachReasoningControlSendsItsExactWireValueAndRetainsContinuationIdentity() throws {
        var identities = Set<String>()
        for effort in ReasoningEffort.allCases {
            let backend = try NetworkModelBackend(baseURL: URL(string: "https://api.openai.com/v1")!, model: "gpt-6.1-sol", wireProtocol: .responses, reasoningEffort: effort)
            identities.insert(backend.id)
            let body = try JSONDecoder().decode(JSONValue.self, from: backend.makeRequest(.init(instructions: "", messages: [], tools: [])).httpBody!)
            XCTAssertEqual(body["reasoning"]?["effort"], .string(effort.rawValue))
        }
        XCTAssertEqual(identities.count, 1)
        XCTAssertEqual(ReasoningEffort.xhigh.title, "Extra High")
        XCTAssertEqual(ReasoningEffort.documented(for: "unknown-model"), [])
    }
    func testAccountCatalogLimitsOverrideFallbackEfforts() throws {
        let catalog = try ChatGPTModel.catalog(from: Data(#"{"models":[{"slug":"gpt-6.1-sol","display_name":"Sol","visibility":"list","supported_reasoning_levels":[{"effort":"low"},{"effort":"high"}]},{"slug":"fixture","display_name":"Fixture","visibility":"list","supported_reasoning_levels":["medium","xhigh","max"]}]}"#.utf8))
        XCTAssertEqual(catalog[0].reasoningEfforts, [.low, .high])
        XCTAssertEqual(catalog[1].reasoningEfforts, [.medium, .xhigh, .max])
    }
    func testMetadataNamingDisablesHostedToolsAndUsesLowEffort() throws {
        let backend = try NetworkModelBackend(baseURL: URL(string: "https://api.openai.com/v1")!, model: "gpt-6.1-sol", wireProtocol: .responses, chatGPTAccountID: "fixture", webSearchEnabled: true, reasoningEffort: .max)
        var request = ModelRequest(instructions: "Name a chat.", messages: [], tools: []); request.isMetadata = true
        let body = try JSONDecoder().decode(JSONValue.self, from: backend.makeRequest(request).httpBody!)
        XCTAssertNil(body["tools"]); XCTAssertEqual(body["reasoning"]?["effort"], .string("low"))
        XCTAssertFalse(body["instructions"]!.stringValue!.contains("Web search is enabled"))
    }
    func testAutomaticNamingUsesConversationTopicAndCannotOverwriteManualRename() async throws {
        let store = try makeTestStore()
        var chat = Conversation()
        chat.messages = [.init(role: .user, text: "Could you help estimate Jupiter's circumference?"), .init(role: .assistant, text: "About 450,000 km with these assumptions.")]
        try await store.save(chat)
        let backend = NamingFixture()
        let title = try await ConversationNamer.generate(for: chat, backend: backend)
        XCTAssertEqual(title, "Estimating Jupiter’s Circumference")
        _ = try await store.saveAutomaticTitle(title!, conversationID: chat.id)
        let named = try await store.loadConversation(chat.id)
        XCTAssertEqual(named.title, title); XCTAssertFalse(named.needsAutomaticTitle)
        try await store.renameConversation(chat.id, title: "My astronomy project")
        let applied = try await store.saveAutomaticTitle("A late model name", conversationID: chat.id)
        XCTAssertFalse(applied)
        let latest = try await store.loadConversation(chat.id)
        XCTAssertEqual(latest.title, "My astronomy project")
    }
    func testNamingDoesNotSendProtectedContextOrInventAnOfflineFallback() async throws {
        var chat = Conversation()
        chat.messages = [.init(role: .user, text: "Secret local note", containsLocalOnlyContext: true), .init(role: .assistant, text: "Private answer", containsLocalOnlyContext: true)]
        let blocked = try await ConversationNamer.generate(for: chat, backend: NamingFixture(destination: "https://example.test"))
        XCTAssertNil(blocked)
        chat.allowedNetworkDestinations.insert("https://example.test")
        let protected = try await ConversationNamer.generate(for: chat, backend: NamingFixture(destination: "https://example.test"))
        XCTAssertNil(protected)
        XCTAssertNil(ConversationNamer.clean("Title\nExplanation"))
        XCTAssertNil(ConversationNamer.clean("https://example.test"))
    }
    func testFilesOutputsAvoidCollisionsAndNeverOverwriteExternalEdits() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let visible = base.appendingPathComponent("Documents/Outputs")
        let store = try LocalStore(root: base.appendingPathComponent("Private"), outputsRoot: visible)
        let id = UUID(), chat = UUID()
        let first = try await store.publishOutput(id: id, filename: "result.csv", data: Data("value\n60.5\n".utf8), conversationID: chat)
        XCTAssertEqual(first?.status, "saved_local")
        XCTAssertEqual(try Data(contentsOf: visible.appendingPathComponent("result.csv")), Data("value\n60.5\n".utf8))
        let second = try await store.publishOutput(id: UUID(), filename: "result.csv", data: Data("different".utf8), conversationID: chat)
        XCTAssertEqual(second?.filename, "result (2).csv")
        try Data("user edit".utf8).write(to: visible.appendingPathComponent("result.csv"))
        _ = try await store.publishOutput(id: id, filename: "result.csv", data: Data("value\n60.5\n".utf8), conversationID: chat)
        XCTAssertEqual(try String(contentsOf: visible.appendingPathComponent("result.csv"), encoding: .utf8), "user edit")
        let reopened = try LocalStore(root: base.appendingPathComponent("Private"), outputsRoot: visible)
        let records = try await reopened.outputRecords()
        XCTAssertEqual(records.count, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: visible.appendingPathComponent("assistant.sqlite").path))
    }
    func testWorkspacePathsRejectTraversalPrefixSiblingsAndLinks() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = base.appendingPathComponent("workspace")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("nested"), withIntermediateDirectories: true)
        for path in ["../secret", "/absolute", "C:\\secret", "nested/../../secret", "nested//bad", ".hidden", "nested/."] {
            XCTAssertThrowsError(try WorkspacePath.resolve(path, inside: root, allowMissingLeaf: true), path)
        }
        XCTAssertEqual(try WorkspacePath.resolve("nested/result.txt", inside: root, allowMissingLeaf: true).lastPathComponent, "result.txt")
        #if !os(Windows)
        let outside = base.appendingPathComponent("workspace-other")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: outside)
        XCTAssertThrowsError(try WorkspacePath.resolve("escape/secret", inside: root, allowMissingLeaf: true))
        #endif
    }
    func testDiffAndVersionChecksPreserveTextAndRefuseStaleWrites() throws {
        let file = FolderFile(workspaceID: UUID(), relativePath: "notes.md", isDirectory: false, byteCount: 10)
        let edit = try FileEditProposal(file: file, original: "Alpha\nOld\nOmega", replacement: "Alpha\nNew\nOmega")
        XCTAssertNoThrow(try edit.validateCurrent(Data(edit.original.utf8)))
        XCTAssertThrowsError(try edit.validateCurrent(Data("Edited elsewhere".utf8)))
        let lines = TextDiffLine.compare(before: edit.original, after: edit.replacement)
        XCTAssertEqual(lines.filter { $0.kind != .added }.map(\.text).joined(separator: "\n"), edit.original)
        XCTAssertEqual(lines.filter { $0.kind != .removed }.map(\.text).joined(separator: "\n"), edit.replacement)
    }
    func testCapabilitiesDescribeActualToolsAndReceiptCancellationStaysDistinct() async throws {
        let store = try makeTestStore()
        let tools = AssistantTools(store: store, conversationID: UUID(), captureIDs: [], sandbox: JavaScriptSandbox(), compactCatalog: true)
        let result = try await tools.execute(.init(id: "caps", name: "get_capabilities", arguments: .object([:])))
        XCTAssertTrue(result.succeeded)
        let names = result.output["tools"]!.arrayValue!.compactMap { $0["name"]?.stringValue }
        XCTAssertTrue(names.contains("run_javascript")); XCTAssertFalse(names.contains("read_capture")); XCTAssertFalse(names.contains("read_memory"))
        XCTAssertLessThan(try result.modelText().utf8.count, 9500)
        let cancelled = ToolResult(callID: "export", name: "export_artifact", succeeded: false, output: .object(["status": .string("cancelled")]))
        let receipt = try JSONValue.parse(cancelled.modelText())
        XCTAssertEqual(receipt["status"], .string("cancelled")); XCTAssertEqual(receipt["tool_succeeded"], .bool(false)); XCTAssertNotNil(receipt["completed_at"])
    }
}

private struct NamingFixture: ModelBackend {
    var destination: String? = nil
    var id: String { "naming-fixture" }
    var networkDestination: String? { destination }
    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        AsyncThrowingStream { continuation in
            guard request.isMetadata, request.tools.isEmpty else { continuation.finish(throwing: AssistantError.invalidTool("Naming must be a metadata request without tools.")); return }
            continuation.yield(.textDelta("Estimating Jupiter’s Circumference")); continuation.yield(.completed); continuation.finish()
        }
    }
}
