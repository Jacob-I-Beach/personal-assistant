import Foundation
import XCTest
@testable import AssistantCore

final class ResponseCompletionTests: XCTestCase, @unchecked Sendable {
    private func event(_ text: String) -> ServerSentEvent { ServerSentEvent(event: nil, data: text) }
    private func text(_ events: [ModelEvent]) -> String {
        events.compactMap { if case .responseContent(let parts) = $0 { ResponsePresentation.text(in: parts) } else { nil } }.last ?? ""
    }
    func testFinalOnlyImageAnswerIsDisplayed() throws {
        var decoder = ModelWireDecoder(wireProtocol: .responses)
        let result = try decoder.consume(event(#"{"type":"response.completed","response":{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"The image contains a blue mug."}]}]}}"#))
        XCTAssertEqual(text(result), "The image contains a blue mug.")
        XCTAssertTrue(decoder.completed)
    }
    func testEmptyTerminalOutputDoesNotDiscardAnAlreadyFinishedToolRequest() throws {
        var decoder = ModelWireDecoder(wireProtocol: .responses)
        let before = try decoder.consume(event(#"{"type":"response.output_item.done","output_index":1,"item":{"type":"function_call","status":"completed","call_id":"calculation","name":"run_javascript","arguments":"{\"code\":\"return 7;\",\"input_json\":\"null\"}"}}"#))
        XCTAssertTrue(before.isEmpty)
        let finished = try decoder.consume(event(#"{"type":"response.completed","response":{"status":"completed","output":[]}}"#))
        let calls = finished.compactMap { if case .toolCall(let call) = $0 { call } else { nil } }
        XCTAssertEqual(calls.map(\.name), ["run_javascript"])
        XCTAssertEqual(calls.first?.arguments["code"], .string("return 7;"))
    }
    func testDoneTextFillsMissingTailWithoutDuplicatingStreamedUnicode() throws {
        var decoder = ModelWireDecoder(wireProtocol: .responses)
        var events = try decoder.consume(event(#"{"type":"response.output_text.delta","delta":"Hello 🌎"}"#))
        events += try decoder.consume(event(#"{"type":"response.output_text.done","output_index":0,"content_index":0,"text":"Hello 🌎!"}"#))
        events += try decoder.consume(event(#"{"type":"response.completed","response":{"status":"completed","output":[]}}"#))
        XCTAssertEqual(text(events), "Hello 🌎!")
    }
    func testRefusalIsVisibleAndBlankCompletionIsAnError() throws {
        var refused = ModelWireDecoder(wireProtocol: .responses)
        var events = try refused.consume(event(#"{"type":"response.refusal.delta","delta":"I cannot "}"#))
        events += try refused.consume(event(#"{"type":"response.completed","response":{"output":[{"type":"message","content":[{"type":"refusal","refusal":"I cannot help with that image."}]}]}}"#))
        XCTAssertEqual(text(events), "I cannot help with that image.")
        var blank = ModelWireDecoder(wireProtocol: .responses)
        XCTAssertThrowsError(try blank.consume(event(#"{"type":"response.completed","response":{"status":"completed","output":[]}}"#))) { error in
            XCTAssertTrue(error.localizedDescription.contains("without an answer"))
        }
        XCTAssertFalse(blank.completed)
    }
    func testTerminalStatusAndIncompleteToolCannotClaimSuccess() throws {
        for payload in [
            #"{"type":"response.completed","response":{"status":"incomplete","output":[]}}"#,
            #"{"type":"response.completed","response":{"status":"completed","output":[{"type":"function_call","status":"incomplete","call_id":"x","name":"run_javascript","arguments":"{}"}]}}"#
        ] {
            var decoder = ModelWireDecoder(wireProtocol: .responses)
            XCTAssertThrowsError(try decoder.consume(event(payload)))
            XCTAssertFalse(decoder.completed)
        }
    }
    func testAccountWebSearchKeepsOwnToolsAndImageInputAndCanBeDisabled() throws {
        let enabled = try NetworkModelBackend(baseURL: URL(string: "https://api.openai.com/v1")!, model: "fixture", wireProtocol: .responses, chatGPTAccountID: "fixture", webSearchEnabled: true)
        let disabled = try NetworkModelBackend(baseURL: URL(string: "https://api.openai.com/v1")!, model: "fixture", wireProtocol: .responses, chatGPTAccountID: "fixture")
        let image = ModelImage(captureID: UUID(), jpeg: Data([0xFF,0xD8,0xFF,0xD9]))
        let input = ModelRequest(instructions: "fixture", messages: [ModelInputMessage(message: Message(role: .user, text: "Inspect"), images: [image])], tools: [CaptureToolBroker.definition])
        let body = try JSONDecoder().decode(JSONValue.self, from: enabled.makeRequest(input).httpBody!)
        XCTAssertEqual(body["tools"]?.arrayValue?.map { $0["type"]?.stringValue }, ["namespace", "web_search"])
        XCTAssertEqual(body["input"]?.arrayValue?.first?["content"]?.arrayValue?.last?["image_url"], .string("data:image/jpeg;base64," + image.jpeg.base64EncodedString()))
        let noWeb = try JSONDecoder().decode(JSONValue.self, from: disabled.makeRequest(input).httpBody!)
        XCTAssertEqual(noWeb["tools"]?.arrayValue?.count, 1)
        XCTAssertNotEqual(enabled.id, disabled.id)
        XCTAssertThrowsError(try NetworkModelBackend(baseURL: URL(string: "https://api.openai.com/v1")!, model: "fixture", wireProtocol: .responses, webSearchEnabled: true))
    }
    func testWebSourcesAreClickableURLsDeduplicatedAndRetainedInMessages() throws {
        var decoder = ModelWireDecoder(wireProtocol: .responses)
        let activity = try decoder.consume(event(#"{"type":"response.web_search_call.searching"}"#))
        guard case .activity("Searching the web") = activity.first else { return XCTFail("Missing search activity") }
        let events = try decoder.consume(event(#"{"type":"response.completed","response":{"output":[{"type":"message","content":[{"type":"output_text","text":"A sourced fact.","annotations":[{"type":"url_citation","title":"Fixture source","url":"https://example.test/fact"},{"type":"url_citation","title":"Repeated","url":"https://example.test/fact"},{"type":"url_citation","title":"Unsafe","url":"javascript:alert(1)"}]}]}]}}"#))
        let sources = events.flatMap { if case .responseContent(let parts) = $0 { parts.flatMap(\.citations) } else { [] as [WebCitation] } }
        XCTAssertEqual(sources.count, 1)
        var message = Message(role: .assistant, text: "A sourced fact.")
        message.citations = sources
        let decoded = try JSONDecoder().decode(Message.self, from: JSONEncoder().encode(message))
        XCTAssertEqual(decoded.citations, sources)
        XCTAssertNil(WebCitation(title: "unsafe", url: "https://user:password@example.test"))
    }
}
