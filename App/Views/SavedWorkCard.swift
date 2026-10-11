import AssistantCore
import SwiftUI

struct SavedWorkCard: View {
    @EnvironmentObject private var model: AppModel
    let work: WorkTurn
    @State private var showContext = false
    private var canRetryContext: Bool { work.permitsContextRetry(maximumTextBytes: model.contextBudget(for: model.settings)?.textByteBudget ?? 0) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Saved progress", systemImage: "arrow.clockwise.circle").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Text(work.goal.isEmpty ? "Continue with your attachment" : work.goal).font(.subheadline).lineLimit(2)
            Text(model.conversation.messages.last?.failureReason == work.reason ? "The request and completed action results are kept here." : work.reason ?? "The request and completed action results are kept here.").font(.caption).foregroundStyle(.secondary)
            if work.needsChangedRequest == true && !canRetryContext {
                if model.contextBudget(for: model.settings) != nil {
                    Button("Adjust working context", systemImage: "text.alignleft") { showContext = true }.font(.subheadline)
                    Text("Use a larger supported context, then continue here, or send a shorter request.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("This runtime cannot enlarge its context here. Send a shorter request below; the completed work stays saved.").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Button { Task { await model.resumeReply(work) } } label: {
                    Label("Continue reply", systemImage: "arrow.right").font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                }.disabled(model.isRunning)
                if work.interruptionKind == "output_limit" {
                    Button("Make more room for the reply", systemImage: "brain") { showContext = true }.font(.caption)
                }
            }
        }.padding(16).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
            .sheet(isPresented: $showContext) { ContextWindowView() }
    }
}
