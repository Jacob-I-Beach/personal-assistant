import AssistantCore
import Foundation

enum ComputerActionReview {
    static let definition = ToolDefinition(name: "review_computer_action", description: "Show the exact computer action for review. Approval applies only to this saved request; it does not authorize other commands or actions.", parameters: .object([
        "type": .string("object"), "properties": .object(["title": .object(["type": .string("string")]), "detail": .object(["type": .string("string")])]),
        "required": .array([.string("title"), .string("detail")]), "additionalProperties": .bool(false)
    ]))
}

extension AppModel {
    func reviewComputerAction(_ call: ToolCall) async throws -> ToolResult {
        let status = try await reviewNativeAction(.init(kind: .approval,
            title: String((call.arguments["title"]?.stringValue ?? "Computer action").prefix(120)),
            detail: String((call.arguments["detail"]?.stringValue ?? "").prefix(110_000)), arguments: call.arguments))
        return ToolResult(callID: call.id, name: call.name, succeeded: true, output: .object(["status": .string(status)]))
    }
}
