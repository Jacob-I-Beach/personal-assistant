import AssistantCore
import SwiftUI

struct SavedWorkCard: View {
    @EnvironmentObject private var model: AppModel
    let work: WorkTurn
    @State private var showContext = false
    @State private var uncertain: [String] = []
    @State private var receiptsChecked = false
    private var needsComputerSync: Bool { ["computer_detached", "computer_sync_attention"].contains(work.interruptionKind ?? "") }
    private var canRetryContext: Bool { work.permitsContextRetry(maximumTextBytes: model.settings.choice == .localMLX ? model.localContextBudget().inputTokens * 3 : model.contextBudget(for: model.settings)?.textByteBudget ?? 0) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(needsComputerSync ? "Saved task · waiting to sync" : "Saved progress", systemImage: "arrow.clockwise.circle").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Text(work.goal.isEmpty ? "Continue with your attachment" : work.goal).font(.subheadline).lineLimit(2)
            Text(model.conversation.messages.last?.failureReason == work.reason ? "The request and completed action results are kept here." : work.reason ?? "The request and completed action results are kept here.").font(.caption).foregroundStyle(.secondary)
            if !receiptsChecked && !needsComputerSync {
                ProgressView("Reading saved action receipts").controlSize(.small)
            } else if !uncertain.isEmpty && !needsComputerSync {
                Text("An action has no confirmed outcome. Inspect its saved evidence before making another request.").font(.caption).foregroundStyle(.secondary)
                Button("Inspect what happened", systemImage: "list.bullet.rectangle") { Task {
                    if let summary = model.histories.first(where: { $0.id == work.conversationID }), model.conversation.id != work.conversationID { await model.selectConversation(summary) }
                    guard model.conversation.id == work.conversationID else { return }
                    model.present(.task)
                } }.disabled(model.isRunning)
            } else if work.backendID.hasPrefix("companion:"), model.settings.choice != .chatGPT {
                Button("Choose ChatGPT to open this saved task", systemImage: "sparkles") { model.showModels = true }.font(.subheadline)
                Text("New messages use \(model.modelTitle). This earlier task keeps its original model.").font(.caption).foregroundStyle(.secondary)
            } else if work.needsChangedRequest == true && !canRetryContext {
                if model.contextBudget(for: model.settings) != nil || model.settings.choice == .localMLX {
                    Button("Adjust working context", systemImage: "text.alignleft") { showContext = true }.font(.subheadline)
                    Text("Use a larger supported context, then continue here, or send a shorter request.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("This runtime cannot enlarge its context here. Send a shorter request below; the completed work stays saved.").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Button { Task { await model.resumeReply(work, reconnectOnly: needsComputerSync) } } label: {
                    Label(needsComputerSync ? "Sync latest reply" : "Continue reply", systemImage: "arrow.right").font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                }.disabled(model.isRunning)
                if work.interruptionKind == "output_limit" {
                    Button("Make more room for the reply", systemImage: "brain") { showContext = true }.font(.caption)
                }
            }
        }.padding(16).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
            .task(id: work.updatedAt) { receiptsChecked = false; do { uncertain = try await model.store?.uncertainOperationNames(work.id) ?? [] } catch { uncertain = ["Unavailable receipt"] }; receiptsChecked = true }
            .sheet(isPresented: $showContext) { ContextWindowView() }
    }
}
