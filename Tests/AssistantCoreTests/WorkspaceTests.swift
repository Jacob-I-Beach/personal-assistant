import Foundation
import XCTest
@testable import AssistantCore

final class WorkspaceTests: XCTestCase, @unchecked Sendable {
    func testInlineSourcesSurviveUnicodeAndRejectOverlappingRanges() throws {
        let text = "🌌 Fact \u{E200}cite\u{E202}source\u{E201}. More."
        let start = 7, end = 21
        let citation = try XCTUnwrap(WebCitation(title: "Source", url: "https://example.com/fact", startIndex: start, endIndex: end))
        let overlapping = try XCTUnwrap(WebCitation(title: "Another", url: "https://example.org/", startIndex: 0, endIndex: 20))
        let message = Message(role: .assistant, text: text, citations: [citation, overlapping])
        XCTAssertTrue(message.citationMarkdown.contains("[1](<https://example.com/fact>)"))
        XCTAssertTrue(message.citationMarkdown.contains("🌌 Fact"))
        XCTAssertFalse(message.citationMarkdown.contains("cite"))
        XCTAssertEqual(message.text, text)
    }
    func testTextArtifactCannotMasqueradeAsBinaryPDF() async throws {
        let store = try makeTestStore()
        let tools = AssistantTools(store: store, conversationID: UUID(), captureIDs: [], sandbox: JavaScriptSandbox())
        let result = try await tools.execute(ToolCall(id: "fake", name: "create_artifact", arguments: .object(["filename": .string("report.pdf"), "content": .string("This is only plain text")])))
        XCTAssertFalse(result.succeeded)
        let files = try await store.artifacts()
        XCTAssertTrue(files.isEmpty)
    }
    func testOriginalsRemainExactAndRequireExplicitSharingOrAttachment() async throws {
        let store = try makeTestStore(), chat = Conversation()
        let data = Data("a,b\n1,2\n".utf8)
        let file = WorkspaceFile(filename: "source.csv", mediaType: "text/csv", byteCount: data.count, text: "a,b\n1,2\n")
        try await store.saveWorkspaceFile(file, data: data)
        let url = try await store.workspaceFileURL(file.id)
        XCTAssertEqual(try Data(contentsOf: url), data)
        let hidden = try await store.readableFiles(attached: [], workspace: true, remote: true, conversationID: chat.id)
        XCTAssertTrue(hidden.isEmpty)
        let attached = try await store.readableFiles(attached: [file.id], workspace: false, remote: true, conversationID: chat.id)
        XCTAssertEqual(attached.map(\.id), [file.id])
        try await store.setFileSharing(file.id, workspace: true, connected: false)
        let local = try await store.readableFiles(attached: [], workspace: true, remote: false, conversationID: chat.id)
        let remote = try await store.readableFiles(attached: [], workspace: true, remote: true, conversationID: chat.id)
        XCTAssertEqual(local.count, 1); XCTAssertTrue(remote.isEmpty)
        try await store.setFileSharing(file.id, workspace: true, connected: true)
        let shared = try await store.readableFiles(attached: [], workspace: true, remote: true, conversationID: chat.id)
        XCTAssertEqual(shared.count, 1)
        do { try await store.saveWorkspaceFile(file, data: data); XCTFail("Overwrote original") } catch {}
        try await store.removeWorkspaceFile(file.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
    func testUnsafeNamesAndHealthResharingAreRejected() async throws {
        for name in ["../secret.txt", "a\\b", ".hidden", "a:b", "bad\nname", "tail.", " "] {
            XCTAssertThrowsError(try WorkspaceFile.validateFilename(name))
        }
        let store = try makeTestStore(), owner = UUID()
        let file = WorkspaceFile(filename: "health.txt", mediaType: "text/plain", byteCount: 1, text: "h", conversationID: owner, containsHealthData: true)
        try await store.saveWorkspaceFile(file, data: Data("h".utf8))
        do { try await store.setFileSharing(file.id, workspace: true, connected: true); XCTFail("Health reshared") } catch {}
        let wrongChat = try await store.readableFiles(attached: [file.id], workspace: true, remote: false, conversationID: UUID())
        XCTAssertTrue(wrongChat.isEmpty)
    }
    func testWorkspaceReadIsScopedAndPaginatesWithoutSplittingUnicode() async throws {
        let store = try makeTestStore(), chat = Conversation()
        try await store.save(chat)
        let body = String(repeating: "🌌 source\n", count: 800)
        let file = WorkspaceFile(filename: "source.md", mediaType: "text/markdown", byteCount: body.utf8.count, text: body)
        try await store.saveWorkspaceFile(file, data: Data(body.utf8))
        let call = ToolCall(id: "read", name: "read_workspace", arguments: .object(["kind": .string("file"), "id": .string(file.id.uuidString), "conversation_id": .string(""), "offset": .string("0")]))
        let blocked = try await AssistantTools(store: store, conversationID: chat.id, captureIDs: [], sandbox: JavaScriptSandbox(), remote: true).execute(call)
        XCTAssertFalse(blocked.succeeded)
        let allowed = try await AssistantTools(store: store, conversationID: chat.id, captureIDs: [], sandbox: JavaScriptSandbox(), remote: true, fileIDs: [file.id], compactCatalog: true).execute(call)
        XCTAssertTrue(allowed.succeeded)
        let text = try XCTUnwrap(allowed.output["text"]?.stringValue)
        XCTAssertLessThanOrEqual(text.utf8.count, 1800); XCTAssertTrue(body.hasPrefix(text)); XCTAssertFalse(text.contains("�"))
    }
    func testCompactDiscoveryExecutesRealSandboxAndKeepsReceiptIdentity() async throws {
        let store = try makeTestStore(), chat = Conversation()
        try await store.save(chat)
        let tools = AssistantTools(store: store, conversationID: chat.id, captureIDs: [], sandbox: JavaScriptSandbox(), compactCatalog: true)
        let discovered = try await tools.execute(ToolCall(id: "find", name: "find_tools", arguments: .object(["query": .string("run_javascript")])))
        XCTAssertEqual(discovered.output.arrayValue?.first?["name"]?.stringValue, "run_javascript")
        let args = try JSONValue.object(["code": .string("return 18.5 + 27.25 + 14.75;"), "input_json": .string("null")]).jsonString()
        let executed = try await tools.execute(ToolCall(id: "real", name: "use_tool", arguments: .object(["name": .string("run_javascript"), "arguments_json": .string(args)])))
        XCTAssertTrue(executed.succeeded); XCTAssertEqual(executed.callID, "real"); XCTAssertEqual(executed.name, "use_tool")
        XCTAssertEqual(executed.output["result"], .number(60.5))
        _ = try ContextPlanner.select([Message(role: .user, text: "Calculate a sum")], instructions: AssistantInstructions.base, tools: tools.definitions, limits: ContextLimits(maximumTextBytes: 10_000))
    }
    func testPlanRejectsInventedStatusAndNativeFileWirePreservesOriginal() async throws {
        let store = try makeTestStore()
        let tools = AssistantTools(store: store, conversationID: UUID(), captureIDs: [], sandbox: JavaScriptSandbox())
        let invalid = try await tools.execute(ToolCall(id: "plan", name: "update_plan", arguments: .object(["steps_json": .string("[{\"title\":\"Research\",\"status\":\"magic\"}]")])))
        XCTAssertFalse(invalid.succeeded)
        let valid = try await tools.execute(ToolCall(id: "plan2", name: "update_plan", arguments: .object(["steps_json": .string("[{\"title\":\"Research\",\"status\":\"in_progress\"}]")])))
        XCTAssertTrue(valid.succeeded)
        let backend = try NetworkModelBackend(baseURL: URL(string: "https://api.openai.com/v1")!, model: "fixture", wireProtocol: .responses, chatGPTAccountID: "fixture")
        let data = Data("%PDF-synthetic".utf8)
        let request = ModelRequest(instructions: "Read the file", messages: [ModelInputMessage(message: Message(role: .user, text: "Read"), files: [ModelFile(filename: "sample.pdf", mediaType: "application/pdf", data: data)])], tools: [])
        let body = try JSONDecoder().decode(JSONValue.self, from: XCTUnwrap(backend.makeRequest(request).httpBody))
        let file = body["input"]?.arrayValue?.first?["content"]?.arrayValue?.last
        XCTAssertEqual(file?["type"], .string("input_file"))
        XCTAssertEqual(file?["file_data"], .string("data:application/pdf;base64," + data.base64EncodedString()))
    }
}
