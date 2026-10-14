import XCTest
@testable import AssistantCore

final class PublishedFileTests: XCTestCase {
    func testPublishedImageBecomesAVisibleAttachmentOutsideTheToolDisclosure() throws {
        let file = UUID(), job = UUID()
        let event: JSONValue = .object(["seq": .number(1), "type": .string("executed_tool"),
            "call": .object(["id": .string("show"), "name": .string("publish_task_files"), "arguments": .object([:])]),
            "result": .object(["callID": .string("show"), "name": .string("publish_task_files"), "succeeded": .bool(true), "output": .object(["caption": .string("The requested screenshot"),
                "presented_files": .array([.object(["id": .string(file.uuidString)])])])])])
        var transcript = CompanionTranscript(jobID: job, providerID: "computer", health: false)
        _ = try transcript.apply(event)
        XCTAssertEqual(transcript.messages.last?.role, .assistant)
        XCTAssertEqual(transcript.messages.last?.fileIDs, [file])
        let identity = transcript.messages.last?.id
        _ = try transcript.apply(event)
        XCTAssertEqual(transcript.messages.last?.id, identity)
        XCTAssertEqual(transcript.messages.filter { !$0.fileIDs.isEmpty }.count, 1)
    }
    func testImageOnlyDisplayMessageDoesNotBecomeAnEmptyProviderMessage() throws {
        let backend = try NetworkModelBackend(baseURL: URL(string: "https://api.openai.com/v1")!, model: "synthetic", wireProtocol: .responses)
        let request = ModelRequest(instructions: "Synthetic", messages: [
            .init(message: Message(role: .user, text: "Describe this")),
            .init(message: Message(role: .assistant, text: "", fileIDs: [UUID()]), files: [.init(filename: "screen.png", mediaType: "image/png", data: Data([1]), id: UUID())])
        ], tools: [])
        let body = try backend.responsesBody(request, includeFileContents: false)
        XCTAssertEqual(body["input"]?.arrayValue?.count, 1)
    }
}
