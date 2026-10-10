#if DEBUG
import AssistantCore
import Foundation
import UIKit

extension AppModel {
    func installInteractionFixture() async {
        guard let store else { return }
        do {
            settings.choice = .appleOnDevice
            var chat = Conversation(id: UUID(uuidString: "00000000-0000-4000-8000-000000000050")!, title: "Interaction checks")
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 240))
            let image = renderer.image { context in
                UIColor.darkGray.setFill(); context.fill(CGRect(x: 0, y: 0, width: 300, height: 240))
                UIColor.lightGray.setFill(); context.fill(CGRect(x: 30, y: 30, width: 240, height: 180))
                ("Synthetic depth fixture" as NSString).draw(at: CGPoint(x: 45, y: 108), withAttributes: [.font: UIFont.systemFont(ofSize: 18), .foregroundColor: UIColor.black])
            }
            let capture = CaptureObservation(source: "Synthetic camera + depth", imageWidth: 300, imageHeight: 240,
                depth: .init(width: 10, height: 8, meters: Array(repeating: 2, count: 80), confidence: Array(repeating: 2, count: 80)),
                cameraIntrinsics: [300,0,0,0,300,0,149.5,119.5,1], trackingState: "normal")
            try await store.saveCapture(capture, jpeg: image.jpegData(compressionQuality: 0.9)!)
            let board = ToolCall(id: UUID().uuidString, name: "present_surface", arguments: .object([:]))
            let chart = ToolCall(id: UUID().uuidString, name: "present_surface", arguments: .object([:]))
            let scenario = ToolCall(id: UUID().uuidString, name: "present_surface", arguments: .object([:]))
            chat.messages = [Message(role: .user, text: "1+1"), Message(role: .assistant, text: "2"),
                Message(role: .user, text: "This later message must disappear after editing."),
                Message(role: .assistant, text: "Here are three synthetic working surfaces.", toolCalls: [board, chart, scenario])]
            try await store.save(chat)
            for (call, raw) in [
                (board, #"{"kind":"comparison","title":"Compare approaches","data":[{"id":"a","label":"Option A","detail":"A concise approach"},{"id":"b","label":"Option B","detail":"A more detailed approach"}]}"#),
                (chart, #"{"kind":"chart","title":"Verified sample values","data":[{"label":"First","value":18.5},{"label":"Second","value":27.25},{"label":"Third","value":14.75}]}"#),
                (scenario, #"{"kind":"scenario","title":"Adjust the estimate","inputs":[{"id":"count","label":"Count","value":4,"min":1,"max":10,"step":1}],"expression":{"op":"multiply","args":[18.5,{"input":"count"}]},"result_label":"Total"}"#)
            ] {
                let surface = try WorkSurface(conversationID: chat.id, sourceCallID: call.id, spec: JSONValue.parse(raw), localOnly: false, health: false)
                try await store.saveSurface(surface)
                let result = ToolResult(callID: call.id, name: call.name, succeeded: true, output: .object(["surface_id": .string(surface.id.uuidString)]))
                chat.messages.append(Message(role: .tool, text: try result.modelText(), toolCallID: call.id))
            }
            chat.messages.append(Message(role: .user, text: "", captureIDs: [capture.id]))
            chat.messages.append(Message(role: .assistant, text: "Open the image to inspect the saved synthetic depth."))
            try await store.save(chat)
            conversation = try await store.loadConversation(chat.id)
        } catch { errorMessage = error.localizedDescription }
    }
}
struct UIInteractionBackend: ModelBackend {
    var id: String { "synthetic-interaction-fixture" }
    var networkDestination: String? { nil }
    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        AsyncThrowingStream { output in
            let old = request.messages.contains { $0.message.text == "1+1" || $0.message.text.contains("This later message must disappear") }
            let correct = request.messages.last?.message.text == "1+2" && !old
            output.yield(.textDelta(correct ? "3" : "The synthetic check did not receive the expected replacement context."))
            output.yield(.completed); output.finish()
        }
    }
}
#endif
