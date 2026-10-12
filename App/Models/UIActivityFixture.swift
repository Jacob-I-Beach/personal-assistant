#if DEBUG
import AssistantCore
import SwiftUI

extension AppModel {
    func installActivityFixture() async {
        guard let store else { return }
        settings.choice = .appleOnDevice; settings.automaticChatTitles = false
        settings.continueInBackground = false; settings.taskNotifications = false
        settings.weatherPlace = nil; settings.weatherFollowsLocation = false
        var chat = Conversation(title: "Activity presentation example")
        chat.messages = [Message(role: .user, text: "Compare the walking trails and make a short checklist.")]
        do {
            for index in 0..<3 {
                let call = ToolCall(id: "example-read-\(index)", name: "read_conversation", arguments: .object([:]))
                let result = ToolResult(callID: call.id, name: call.name, succeeded: true, output: .object(["title": .string("Earlier trail notes"), "result": .array([.object(["text": .string("A short trail with a clear path is preferred.")])])]))
                chat.messages += [Message(role: .assistant, text: "", toolCalls: [call]), Message(role: .tool, text: try result.modelText(), toolCallID: call.id)]
            }
            let memoryCall = ToolCall(id: "example-memory", name: "read_memory", arguments: .object([:]))
            let memoryResult = ToolResult(callID: memoryCall.id, name: memoryCall.name, succeeded: true, output: .object(["result": .array([])]))
            chat.messages += [Message(role: .assistant, text: "", toolCalls: [memoryCall]), Message(role: .tool, text: try memoryResult.modelText(), toolCallID: memoryCall.id)]
            var response = Message(role: .assistant, text: "The river trail is shorter, while the woodland trail offers more shade. I’m comparing the remaining details.", state: .streaming)
            response.responseParts = [
                ResponsePart(id: "0:search", web: WebActivity(status: "completed", queries: ["city walking trails accessibility shade"], sources: [WebCitation(title: "Example trail guide", url: "https://example.test/trails")!])),
                ResponsePart(id: "1:page", web: WebActivity(status: "completed", action: "open_page", sources: [WebCitation(title: "River and woodland paths", url: "https://example.test/paths")!])),
                ResponsePart(id: "2:answer:0", text: response.text, phase: "final_answer")
            ]
            chat.messages.append(response)
            try await store.save(chat); conversation = chat
            isRunning = true; activity = "Writing your comparison"
        } catch { errorMessage = error.localizedDescription }
    }
    func finishActivityFixture() async {
        guard let store, isRunning else { return }
        do {
            conversation.messages[conversation.messages.count - 1].state = .complete
            let call = ToolCall(id: "example-checklist", name: "present_surface", arguments: .object([:]))
            let surface = try WorkSurface(conversationID: conversation.id, sourceCallID: call.id,
                spec: JSONValue.parse(#"{"kind":"checklist","title":"Before your walk","subtitle":"Keep the useful next steps together.","data":[{"id":"sources","label":"Review the trail sources","detail":"Confirm today’s access and conditions."},{"id":"route","label":"Choose a starting point","detail":"Use the route that suits your available time."}]}"#), localOnly: false, health: false)
            try await store.saveSurface(surface)
            let receipt = ToolResult(callID: call.id, name: call.name, succeeded: true, output: .object(["surface_id": .string(surface.id.uuidString)]))
            conversation.messages += [Message(role: .assistant, text: "", toolCalls: [call]), Message(role: .tool, text: try receipt.modelText(), toolCallID: call.id), Message(role: .assistant, text: "Your comparison and checklist are ready.")]
            try await store.save(conversation); isRunning = false; activity = nil
        } catch { errorMessage = error.localizedDescription }
    }
}

struct ActivityPreviewGallery: View {
    @Environment(\.dismiss) private var dismiss
    @State private var phase = "Working"
    private let started = Date().addingTimeInterval(-85)
    private var attributes: AssistantActivityAttributes {
        AssistantActivityAttributes(conversationID: "synthetic", startedAt: started, onComputer: true, modelName: "GPT-6.1-Sol")
    }
    private var state: AssistantActivityAttributes.ContentState {
        switch phase {
        case "Ready": .init(title: "Your reply is ready", detail: "Tap to open the answer and saved results.", phase: "ready", updatedAt: Date(), finishedAt: started.addingTimeInterval(85))
        case "Waiting": .init(title: "Which trail would you prefer?", detail: "Open this chat to answer or review.", phase: "waiting", updatedAt: Date())
        case "Reconnecting": .init(title: "Updating your progress", detail: "", phase: "reconnecting", updatedAt: Date())
        default: .init(title: "Comparing the trail sources", detail: "", phase: "working", updatedAt: Date(), steps: ["Checked the current trail conditions", "Comparing the trail sources"])
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Picker("Activity state", selection: $phase) {
                        ForEach(["Working", "Ready", "Waiting", "Reconnecting"], id: \.self) { Text($0).tag($0) }
                    }.pickerStyle(.segmented)
                    Text("Compact Island").font(.caption).foregroundStyle(.secondary)
                    HStack { AssistantActivityMark().frame(width: 23, height: 23); Spacer(); AssistantActivityIndicator(state: state) }
                        .padding(.horizontal, 12).frame(width: 220, height: 40).background(.black, in: Capsule()).frame(maxWidth: .infinity)
                    Text("Expanded Island").font(.caption).foregroundStyle(.secondary)
                    VStack(spacing: 12) {
                        HStack { AssistantActivityMark().frame(width: 28, height: 28); Text("GPT-6.1-Sol").font(.caption).foregroundStyle(.secondary); Spacer(); AssistantActivityIndicator(state: state) }
                        AssistantActivityBody(attributes: attributes, state: state)
                    }.padding(18).background(.black, in: RoundedRectangle(cornerRadius: 30))
                    Text("Lock Screen").font(.caption).foregroundStyle(.secondary)
                    AssistantActivityCard(attributes: attributes, state: state).background(Color(white: 0.065), in: RoundedRectangle(cornerRadius: 24))
                }.padding(20)
            }.background(Color(uiColor: .systemGroupedBackground)).navigationTitle("Activity preview").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.environment(\.colorScheme, .dark)
    }
}
#endif
