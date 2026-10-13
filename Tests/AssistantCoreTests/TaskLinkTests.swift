import XCTest
@testable import AssistantCore

final class TaskLinkTests: XCTestCase {
    func testLegacyAndRemoteTaskLinksPreserveExactIdentity() throws {
        let chat = UUID(), job = UUID()
        XCTAssertEqual(AssistantTaskLink(URL(string: "personalassistant://task/\(chat)")!), .chat(conversationID: chat, jobID: nil, serverID: nil))
        XCTAssertEqual(AssistantTaskLink(URL(string: "personalassistant://task/\(chat)?job=\(job)&server=paired-server")!),
            .chat(conversationID: chat, jobID: job, serverID: "paired-server"))
        XCTAssertEqual(AssistantTaskLink(URL(string: "personalassistant://notifications")!), .inbox)
    }
    func testMalformedLinksCannotChooseAnArbitraryServerOrAmbiguousTask() {
        let chat = UUID(), job = UUID()
        for raw in ["personalassistant://task/\(chat)?job=\(job)",
                    "personalassistant://task/\(chat)?job=\(job)&server=https%3A%2F%2Fexample.test",
                    "personalassistant://task/\(chat)?job=\(job)&job=\(UUID())&server=fixture",
                    "personalassistant://task/\(chat)?job", "personalassistant://task/\(chat)/extra",
                    "personalassistant://user@task/\(chat)", "https://task/\(chat)"] {
            XCTAssertNil(AssistantTaskLink(URL(string: raw)!), raw)
        }
    }
}
