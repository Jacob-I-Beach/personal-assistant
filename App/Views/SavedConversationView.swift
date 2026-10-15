import AssistantCore
import SwiftUI

extension AppModel {
    var rootPresentation: AppPresentation? {
        get { presentationState.active }
        set { if let newValue { present(newValue) } else { presentationState.beginDismissal() } }
    }
    func present(_ route: AppPresentation) { presentationState.request(route) }
    func dismissPresentation(_ route: AppPresentation) { presentationState.cancel(route) }
    func didDismissPresentation() {
        let route = presentationState.didDismiss()
        if route?.isReview == true { nativeReviewDidDismiss() }
    }
    var executionOwner: ExecutionOwner? { activeTurnID.map { ExecutionOwner(conversationID: conversation.id, turnID: $0) } }
    func stop(owner: ExecutionOwner) {
        guard owner.matches(conversationID: conversation.id, turnID: activeTurnID) else { return }
        stop()
    }
}
struct ConversationDisplayContext {
    let conversation: Conversation
    var readOnly = true
    var revision: ConversationRevision?
}
private struct ConversationDisplayKey: EnvironmentKey { static let defaultValue: ConversationDisplayContext? = nil }
extension EnvironmentValues {
    var conversationDisplay: ConversationDisplayContext? {
        get { self[ConversationDisplayKey.self] }
        set { self[ConversationDisplayKey.self] = newValue }
    }
}
struct SavedConversationView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var navigation = ChatNavigation()
    @StateObject private var voice = VoiceController()
    @Environment(\.dismiss) private var dismiss
    let id: UUID
    var messageID: UUID?
    var revision: ConversationRevision?
    @State private var chat: Conversation?
    @State private var failure: String?
    @State private var limit = 100
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    if let chat {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            Text(revision == nil ? "Reading saved work. The active response and draft stay in their original chat." : "Earlier transcript. Recorded actions remain facts; viewing this version does not execute them.").font(.caption).foregroundStyle(.secondary)
                            let items = ChatTimeline.items(chat.messages)
                            let center = messageID.flatMap { selected in items.firstIndex { $0.messages.contains { $0.id == selected } } }
                            let lower = center.map { max(0, $0 - 20) } ?? max(0, items.count - limit)
                            let upper = center.map { min(items.count, $0 + 80) } ?? items.count
                            if lower > 0 { Button("Read earlier messages") { limit += 100 }.disabled(center != nil) }
                            ForEach(Array(items[lower..<upper])) { item in
                                Group {
                                    if item.isActivity { ActivityGroupView(messages: item.messages) }
                                    else if let message = item.messages.first { MessageRow(message: message, showsResponseActions: true, compactActions: true) }
                                }.id(item.id).background(item.messages.contains { $0.id == messageID } ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 12))
                            }
                            if let revision, !revision.artifacts.isEmpty {
                                Text("Outputs at this revision").font(.headline)
                                ForEach(revision.artifacts) { document in
                                    DisclosureGroup(document.filename + " · revision \(document.revision)") { Text(document.content).textSelection(.enabled).font(.body.monospaced()) }
                                }
                            }
                        }.padding(20).environment(\.conversationDisplay, ConversationDisplayContext(conversation: chat, revision: revision))
                    } else if let failure { ContentUnavailableView("Could not open chat", systemImage: "bubble", description: Text(failure)) }
                    else { ProgressView("Opening saved conversation") }
                }.task(id: id) {
                    do { navigation.model = model; if let revision { chat = revision.conversation } else { chat = try await model.store?.loadConversation(id) }; if let messageID { guard chat?.messages.contains(where: { $0.id == messageID }) == true else { chat = nil; throw AssistantError.provider("The source message was removed or edited. Open Conversation history to inspect earlier versions.") }; proxy.scrollTo(messageID, anchor: .center) } }
                    catch { failure = error.localizedDescription }
                }
            }
            .navigationDestination(item: $navigation.destination) { target in SavedOutputDestination(destination: target, conversation: chat, revision: revision) }
            .navigationTitle(chat?.title ?? "Saved chat").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if model.isRunning {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) { Text("Working in “\(model.conversation.title)”").font(.subheadline.weight(.medium)); Text(model.activity ?? "Response in progress").font(.caption).foregroundStyle(.secondary) }
                        Spacer(); Button("Return") { dismiss() }.frame(minHeight: 44)
                        if let owner = model.executionOwner { Button("Stop", role: .destructive) { model.stop(owner: owner) }.frame(minHeight: 44).accessibilityLabel("Stop the response in " + model.conversation.title) }
                    }.padding().background(.bar)
                }
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.environmentObject(voice).environmentObject(navigation)
    }
}
struct ConversationRevisionsView: View {
    @EnvironmentObject private var model: AppModel
    let conversationID: UUID
    @State private var revisions: [ConversationRevision] = []
    @State private var restoring: ConversationRevision?
    @State private var failure: String?
    var body: some View {
        NavigationStack {
            List {
                Section { Text("Earlier transcripts and output versions are kept when you edit a request. Restoring changes this chat's transcript only. Sent messages, calendar changes and files outside the app remain unchanged.").font(.subheadline).foregroundStyle(.secondary) }
                ForEach(revisions) { revision in
                    VStack(alignment: .leading, spacing: 10) {
                        NavigationLink { SavedConversationView(id: conversationID, revision: revision) } label: { VStack(alignment: .leading) { Text(revision.reason); Text(revision.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) } }
                        Button("Restore this transcript") { restoring = revision }.disabled(model.isRunning)
                    }.padding(.vertical, 6)
                }
                if revisions.isEmpty { Text("Earlier versions appear here after you edit a request.").foregroundStyle(.secondary) }
                if let failure { Text(failure).foregroundStyle(.secondary) }
            }.navigationTitle("Conversation history")
                .task { await reload() }
                .confirmationDialog("Restore this transcript?", isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } })) {
                    Button("Restore transcript") { if let revision = restoring { Task { await restore(revision) } } }
                    Button("Cancel", role: .cancel) { restoring = nil }
                } message: { Text("Your current version will also be saved. No model request or external action will run.") }
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { model.dismissPresentation(.revisions(conversationID)) } } }
        }
    }
    private func reload() async { do { revisions = try await model.store?.conversationRevisions(conversationID) ?? [] } catch { failure = error.localizedDescription } }
    private func restore(_ revision: ConversationRevision) async {
        guard !model.isRunning, let store = model.store else { return }
        do {
            let expected = try await store.loadConversation(conversationID, preservingStreaming: true)
            guard !model.isRunning else { return }
            _ = try await store.restoreConversationRevision(revision.id, expected: expected)
            await model.refresh()
            if let summary = model.histories.first(where: { $0.id == conversationID }) { await model.selectConversation(summary) }
            restoring = nil; await reload()
        } catch { failure = error.localizedDescription }
    }
}

private struct SavedOutputDestination: View {
    @EnvironmentObject private var model: AppModel
    let destination: ChatDestination
    let conversation: Conversation?
    let revision: ConversationRevision?
    @ViewBuilder var body: some View {
        Group {
            switch destination {
            case .file(let id): WorkspaceFileView(id: id)
            case .capture(let id): CaptureViewer(captureID: id)
            case .artifact(let id):
                if let artifact = revision?.artifacts.first(where: { $0.id == id }) ?? model.artifacts.first(where: { $0.id == id }) {
                    ScrollView { Text(artifact.content).font(.body.monospaced()).textSelection(.enabled).padding(20) }.navigationTitle(artifact.filename)
                }
            case .surface(let id, _): ScrollView { WorkingSurfaceView(id: id, expanded: true).padding() }
            case .outputs: Text("Open individual saved files from the transcript.")
            }
        }.environment(\.conversationDisplay, conversation.map { ConversationDisplayContext(conversation: $0, revision: revision) })
    }
}
