import AssistantCore
import SwiftUI

struct SurfaceDetailView: View {
    @EnvironmentObject private var model: AppModel
    let id: UUID
    var selectedRevision: Int?
    @State private var revision: Int?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let selectedRevision, let revision, selectedRevision != revision {
                    Text("The message selected revision \(selectedRevision). This is the current saved revision, \(revision).").font(.subheadline).foregroundStyle(.secondary)
                }
                WorkingSurfaceView(id: id, expanded: true, revisionChanged: { revision = $0 })
            }.padding(20)
        }.navigationTitle("Working view").navigationBarTitleDisplayMode(.inline)
            .task { revision = try? await model.store?.surfaces(conversationID: model.conversation.id).first(where: { $0.id == id })?.revision }
    }
}
