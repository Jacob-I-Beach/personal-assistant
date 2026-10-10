import AssistantCore
import SwiftUI

struct SavedWorkCard: View {
    @EnvironmentObject private var model: AppModel
    let work: WorkTurn
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Saved progress", systemImage: "arrow.clockwise.circle").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Text(work.goal.isEmpty ? "Continue with your attachment" : work.goal).font(.subheadline).lineLimit(2)
            Text("The request and completed action results are kept here.").font(.caption).foregroundStyle(.secondary)
            Button { Task { await model.resumeReply(work) } } label: {
                Label("Continue reply", systemImage: "arrow.right").font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
            }.disabled(model.isRunning)
        }.padding(16).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
