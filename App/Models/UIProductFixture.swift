#if DEBUG
import AssistantCore
import Foundation
import UIKit

extension AppModel {
    func installProductFixture() async {
        guard let store else { return }
        settings.choice = .appleOnDevice; settings.automaticChatTitles = false
        settings.speakReplies = false; settings.continueInBackground = false; settings.taskNotifications = false
        do {
            var chat = Conversation(id: UUID(uuidString: "00000000-0117-4000-8000-000000000001")!, title: "Product journey example")
            if ProcessInfo.processInfo.arguments.contains("--ui-product117-search") {
                chat.messages = (0..<240).map { Message(role: .assistant, text: $0 == 9 ? "Exact old result: amber telescope" : "Saved example paragraph \($0).") }
            }
            try await store.save(chat)
            let artifact = ArtifactRecord(id: UUID(uuidString: "00000000-0117-4000-8000-000000000002")!, conversationID: chat.id, filename: "journey-notes.md", content: "# Saved document\n\nOriginal saved text.")
            if (try? await store.artifactRecord(artifact.id)) == nil { try await store.saveArtifact(artifact) }
            let data = Data("name,value\nFirst,=1+1\nSecond,\"a,b\"\n".utf8)
            let file = WorkspaceFile(id: UUID(uuidString: "00000000-0117-4000-8000-000000000003")!, filename: "journey-table.csv", mediaType: "text/csv", byteCount: data.count, text: String(decoding: data, as: UTF8.self), conversationID: chat.id)
            if (try? await store.workspaceFile(file.id)) == nil { try await store.saveWorkspaceFile(file, data: data) }
            let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { context in
                context.beginPage()
                ("Synthetic preview of the original PDF." as NSString).draw(at: CGPoint(x: 40, y: 80), withAttributes: [.font: UIFont.systemFont(ofSize: 24), .foregroundColor: UIColor.black])
            }
            let document = WorkspaceFile(id: UUID(uuidString: "00000000-0117-4000-8000-000000000004")!, filename: "journey-preview.pdf", mediaType: "application/pdf", byteCount: pdf.count, text: "Synthetic preview of the original PDF.", conversationID: chat.id)
            if (try? await store.workspaceFile(document.id)) == nil { try await store.saveWorkspaceFile(document, data: pdf) }
            if ProcessInfo.processInfo.arguments.contains("--ui-product117-surfaces") {
                let call = ToolCall(id: "product-surface", name: "present_surface", arguments: .object([:]))
                let spec = try JSONValue.parse(#"{"kind":"scenario","title":"Plan a short session","inputs":[{"id":"count","label":"Minutes","value":20,"min":5,"max":90,"step":5}],"expression":{"op":"multiply","args":[2,{"input":"count"}]},"result_label":"Points"}"#)
                let surface = try WorkSurface(conversationID: chat.id, sourceCallID: call.id, spec: spec, localOnly: false, health: false)
                try await store.saveSurface(surface)
                chat.messages = [Message(role: .user, text: "Prepare an estimate"), Message(role: .assistant, text: "Adjust the estimate below.", toolCalls: [call]), Message(role: .tool, text: try JSONValue.object(["surface_id": .string(surface.id.uuidString)]).jsonString(), toolCallID: call.id)]
                try await store.save(chat)
            }
            conversation = try await store.loadConversation(chat.id); draft = ""; draftContextReferences = []
        } catch { errorMessage = error.localizedDescription }
    }
}
struct UIProductBackend: ModelBackend {
    var id: String { "synthetic-product-journey" }
    var networkDestination: String? { nil }
    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        AsyncThrowingStream { output in output.yield(.textDelta("Synthetic response received the selected context.")); output.yield(.completed); output.finish() }
    }
}
#endif
