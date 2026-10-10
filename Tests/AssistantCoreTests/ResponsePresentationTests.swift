import Foundation
import XCTest
@testable import AssistantCore

final class ResponsePresentationTests: XCTestCase, @unchecked Sendable {
    private func event(_ json: String) -> ServerSentEvent { .init(event: nil, data: json) }
    private func parts(_ events: [ModelEvent]) -> [ResponsePart] {
        events.compactMap { if case .responseContent(let value) = $0 { value } else { nil } }.last ?? []
    }
    private let publicItems = #"""
    [
      {"type":"message","id":"plan","role":"assistant","phase":"commentary","content":[{"type":"output_text","text":"I will verify a reference."}]},
      {"type":"reasoning","encrypted_content":"never-render-this","summary":[{"text":"private-looking-data"}]},
      {"type":"web_search_call","id":"web","status":"completed","action":{"type":"search","queries":["planet reference"],"sources":[{"type":"url","url":"https://example.test/reference"},{"type":"url","url":"javascript:alert(1)"}]}},
      {"type":"message","id":"assumptions","phase":"commentary","content":[{"type":"output_text","text":"No observations were supplied."}]},
      {"type":"function_call","status":"completed","call_id":"calc","name":"run_javascript","arguments":"{\"code\":\"return 60.5;\"}"}
    ]
    """#
    func testOrderedPublicPartsSurviveCompletionAndLegacyReload() throws {
        let items = try JSONValue.parse(publicItems).arrayValue!
        var decoder = ModelWireDecoder(wireProtocol: .responses)
        let events = try decoder.consume(event(#"{"type":"response.completed","response":{"status":"completed","output":"# + publicItems + "}}"))
        let content = parts(events)
        XCTAssertEqual(content.map(\.kind), [.text, .web, .text])
        XCTAssertEqual(content.map(\.phase), ["commentary", nil, "commentary"])
        XCTAssertEqual(content[1].web?.queries, ["planet reference"])
        XCTAssertEqual(content[1].web?.sources.count, 1)
        let text = ResponsePresentation.text(in: content)
        XCTAssertEqual(text, "I will verify a reference.\n\nNo observations were supplied.")
        XCTAssertFalse(text.contains("never-render"))
        let old = Message(role: .assistant, text: "I will verify a reference.No observations were supplied.",
                          continuation: ProviderContinuation(providerID: "fixture", items: items))
        let reloaded = try JSONDecoder().decode(Message.self, from: JSONEncoder().encode(old))
        XCTAssertEqual(reloaded.displayParts, content)
        XCTAssertEqual(reloaded.text, old.text)
        var changed = reloaded; changed.text = "Edited by the user"
        XCTAssertTrue(changed.displayParts.isEmpty)
        let new = Message(role: .assistant, text: text, responseParts: content)
        XCTAssertEqual(try JSONDecoder().decode(Message.self, from: JSONEncoder().encode(new)), new)
    }
    func testStreamingMessageBoundariesAndWebReceiptRemainVisible() throws {
        var decoder = ModelWireDecoder(wireProtocol: .responses)
        _ = try decoder.consume(event(#"{"type":"response.output_item.added","output_index":0,"item":{"type":"message","id":"a","phase":"commentary","content":[]}}"#))
        _ = try decoder.consume(event(#"{"type":"response.output_text.delta","output_index":0,"content_index":0,"delta":"First 🌎"}"#))
        _ = try decoder.consume(event(#"{"type":"response.web_search_call.searching","output_index":1,"item_id":"web"}"#))
        let webDone = try decoder.consume(event(#"{"type":"response.output_item.done","output_index":1,"item":{"type":"web_search_call","id":"web","status":"completed","action":{"type":"open_page","url":"https://example.test/fact"}}}"#))
        XCTAssertEqual(parts(webDone)[1].web?.title, "Read a web page")
        _ = try decoder.consume(event(#"{"type":"response.output_item.added","output_index":2,"item":{"type":"message","id":"b","phase":"commentary","content":[]}}"#))
        let second = try decoder.consume(event(#"{"type":"response.output_text.delta","output_index":2,"content_index":0,"delta":"Second update"}"#))
        XCTAssertEqual(parts(second).map(\.kind), [.text, .web, .text])
        XCTAssertEqual(ResponsePresentation.text(in: parts(second)), "First 🌎\n\nSecond update")
        _ = try decoder.consume(event(#"{"type":"response.output_text.done","output_index":0,"content_index":0,"text":"First 🌎!"}"#))
        let final = try decoder.consume(event(#"{"type":"response.completed","response":{"status":"completed","output":[]}}"#))
        XCTAssertEqual(ResponsePresentation.text(in: parts(final)), "First 🌎!\n\nSecond update")
    }
    func testChangedTerminalTextRejectsAllToolExecution() throws {
        var decoder = ModelWireDecoder(wireProtocol: .responses)
        _ = try decoder.consume(event(#"{"type":"response.output_text.delta","output_index":0,"delta":"Original"}"#))
        XCTAssertThrowsError(try decoder.consume(event(#"{"type":"response.completed","response":{"output":[{"type":"message","content":[{"type":"output_text","text":"Changed"}]},{"type":"function_call","status":"completed","call_id":"x","name":"run_javascript","arguments":"{}"}]}}"#)))
        XCTAssertFalse(decoder.completed)
    }
    func testMissingFinalTextCannotReleaseToolCalls() throws {
        var decoder = ModelWireDecoder(wireProtocol: .responses)
        _ = try decoder.consume(event(#"{"type":"response.output_text.delta","output_index":0,"delta":"Already visible"}"#))
        XCTAssertThrowsError(try decoder.consume(event(#"{"type":"response.completed","response":{"output":[{"type":"message","content":[]},{"type":"function_call","status":"completed","call_id":"x","name":"run_javascript","arguments":"{}"}]}}"#)))
        XCTAssertFalse(decoder.completed)
    }
    func testInterruptedWebActivityDoesNotSpinForeverAndLegacyJSONLoads() throws {
        let content = [ResponsePart(id: "web", web: .init(status: "searching"))]
        var message = Message(role: .assistant, text: "", state: .streaming, responseParts: content)
        XCTAssertTrue(message.displayParts[0].web!.isRunning)
        message.state = .interrupted
        XCTAssertFalse(message.displayParts[0].web!.isRunning)
        XCTAssertFalse(message.displayParts[0].web!.isSuccessful)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(message)) as? [String: Any])
        json.removeValue(forKey: "responseParts")
        let legacy = try JSONDecoder().decode(Message.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(legacy.responseParts.isEmpty)
    }
    func testCitationOffsetsAreLocalToTheirTextPart() throws {
        let items = try JSONValue.parse(#"""
        [{"type":"message","content":[{"type":"output_text","text":"First paragraph."}]},
         {"type":"message","phase":"final_answer","content":[{"type":"output_text","text":"🌎 Fact.","annotations":[{"type":"url_citation","title":"Source","url":"https://example.test/fact","start_index":2,"end_index":7}]}]}]
        """#).arrayValue!
        let content = ResponsePresentation.parts(from: items)
        XCTAssertEqual(content[1].citations.first?.startIndex, 2)
        XCTAssertEqual(Message.citationMarkdown(text: content[1].text, citations: content[1].citations), "🌎 Fact. [1](<https://example.test/fact>)")
        let message = Message(role: .assistant, text: ResponsePresentation.text(in: content), responseParts: content)
        XCTAssertEqual(message.answerText, "🌎 Fact.")
    }
    func testActionsOnlyFollowTheLastCompleteAnswerInEachTurn() {
        var conversation = Conversation()
        let plan = Message(role: .assistant, text: "Working", toolCalls: [ToolCall(id: "x", name: "run_javascript", arguments: .null)])
        let final = Message(role: .assistant, text: "60.5")
        conversation.messages = [Message(role: .user, text: "Add"), plan, Message(role: .tool, text: "60.5", toolCallID: "x"), final]
        XCTAssertEqual(conversation.responseActionMessageIDs(isRunning: false), [final.id])
        XCTAssertEqual(conversation.responseActionMessageIDs(isRunning: true), [])
        conversation.messages += [Message(role: .user, text: "Next"), Message(role: .assistant, text: "Working", state: .streaming)]
        XCTAssertEqual(conversation.responseActionMessageIDs(isRunning: true), [final.id])
        conversation.messages[5].state = .failed
        XCTAssertEqual(conversation.responseActionMessageIDs(isRunning: false), [final.id])
        conversation.messages[5] = Message(role: .assistant, text: "Progress", responseParts: [.init(id: "p", text: "Progress", phase: "commentary")])
        XCTAssertEqual(conversation.responseActionMessageIDs(isRunning: false), [final.id])
    }
    func testProviderPhaseAndOpaqueContinuationAreReplayedUntouched() throws {
        let backend = try NetworkModelBackend(baseURL: URL(string: "https://api.openai.com/v1")!, model: "fixture", wireProtocol: .responses)
        let items = try JSONValue.parse(publicItems).arrayValue!
        let message = Message(role: .assistant, text: "Display text", continuation: .init(providerID: backend.id, items: items))
        let request = try backend.makeRequest(ModelRequest(instructions: "", messages: [.init(message: message)], tools: []))
        let body = try JSONDecoder().decode(JSONValue.self, from: request.httpBody!)
        XCTAssertEqual(body["input"], .array(items))
    }
    func testReadableCalculationFormattingPreservesUnderlyingValues() throws {
        let value = try JSONValue.parse(#"{"circumferenceKm":450270.2390577233,"boundsKm":[433683.820550337,467161.27498489624],"ok":true}"#)
        let fields = ToolResultPresentation.fields(value)
        XCTAssertEqual(fields.map(\.label), ["Bounds Km", "Circumference Km", "Ok"])
        XCTAssertEqual(fields[1].value, "450,270.2391")
        XCTAssertFalse(fields[0].value.contains("{"))
        XCTAssertEqual(value["circumferenceKm"], .number(450270.2390577233))
        let call = ToolCall(id: "x", name: "use_tool", arguments: .object(["arguments_json": .string(#"{"code":"return 60.5;"}"#)]))
        XCTAssertEqual(ToolResultPresentation.arguments(of: call)?["code"], .string("return 60.5;"))
    }
    func testMathDelimitersAreAdaptedWithoutTouchingCode() {
        XCTAssertEqual(MathMarkdown.normalize(#"Angle \(\theta\), \[C \approx \pi d\theta.\]"#),
                       #"Angle $\\theta$, "# + "\n\n" + #"$$C \\approx \\pi d\\theta.$$"# + "\n\n")
        let tick = String(UnicodeScalar(96))
        let source = tick + #"\(\theta\)"# + tick + "\n" + String(repeating: tick, count: 3) + "swift\n" + #"\[x\]"# + "\n" + String(repeating: tick, count: 3)
        XCTAssertEqual(MathMarkdown.normalize(source), source)
        XCTAssertEqual(MathMarkdown.normalize(#"Unfinished \(x"#), #"Unfinished \(x"#)
        XCTAssertEqual(MathMarkdown.normalize(#"Escaped \\(x\\)"#), #"Escaped \\(x\\)"#)
    }
}
