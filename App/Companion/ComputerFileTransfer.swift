import AssistantCore
import Foundation

enum ComputerFileTools {
    static let transfer = CommunicationTools.tool("transfer_file_to_computer", "Make a selected or already-permitted Library file or text artifact available to this task's computer tools by handle. The original bytes stay out of the model request; run_python can return aggregates and inspect_document can return bounded page evidence. Does not grant access to other files. Use list_task_files on the computer to inspect completed uploads after interruption.", [
        "kind": .object(["type": .string("string"), "enum": .array([.string("file"), .string("artifact")])]),
        "id": CommunicationTools.text
    ])
}
extension AppModel {
    func transferFileToComputer(_ call: ToolCall, conversationID: UUID) async throws -> ToolResult {
        guard let store, settings.useComputer, let connection = settings.companion, let turn = ToolExecutionContext.current?.turnID,
              let id = call.arguments["id"]?.stringValue.flatMap(UUID.init(uuidString:)) else { throw AssistantError.invalidTool("Choose a Library file and connect your computer.") }
        let chat = try await store.loadConversation(conversationID)
        let data: Data, name: String, computerID: String, health: Bool
        if call.arguments["kind"] == .string("artifact") {
            guard let artifact = try await store.readableArtifacts(conversationID: conversationID, workspace: settings.workspaceSearchEnabled, remote: true).first(where: { $0.id == id }) else { throw AssistantError.invalidTool("That document is outside the available workspace.") }
            data = Data(artifact.content.utf8); name = artifact.filename; computerID = id.uuidString + "-revision-" + String(artifact.revision); health = artifact.containsHealthData
        } else {
            guard let file = try await store.readableFiles(attached: chat.attachedFileIDs, workspace: settings.workspaceSearchEnabled, remote: true, conversationID: conversationID).first(where: { $0.id == id }) else { throw AssistantError.invalidTool("Attach this file to the chat or enable its connected workspace access.") }
            data = try Data(contentsOf: await store.workspaceFileURL(id)); name = file.filename; computerID = id.uuidString; health = file.containsHealthData
        }
        guard !health || chat.allowedHealthDestinations.contains(connection.destination) else { throw AssistantError.networkNotAuthorized }
        let (client, jobID) = try await computerToolWorkspace(turn: turn, conversationID: conversationID)
        let uploaded = try await client.json("/v1/jobs/" + jobID + "/files", method: "POST", body: .object(["id": .string(computerID), "filename": .string(name), "data_base64": .string(data.base64EncodedString()), "contains_health_data": .bool(health)]))
        var result = ToolResult(callID: call.id, name: call.name, succeeded: true, output: .object(["status": .string("available_on_computer"), "file": uploaded, "notice": .string("Original file transferred to this task's encrypted computer workspace. Its full contents were not included in the model request.")]))
        result.containsHealthData = health; return result
    }
}
