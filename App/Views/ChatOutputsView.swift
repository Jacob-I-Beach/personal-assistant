import AssistantCore
import SwiftUI

struct ChatOutputsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var navigation: ChatNavigation
    let conversationID: UUID
    @State private var source: Conversation?
    var body: some View {
        List {
            let documents = model.artifacts.filter { $0.conversationID == conversationID && source?.excludedArtifactIDs.contains($0.id) != true }
            let superseded = Set(documents.compactMap(\.previousRevisionID))
            ForEach(documents.filter { !superseded.contains($0.id) }) { artifact in
                Button { navigation.destination = .artifact(artifact.id) } label: { ArtifactCard(artifact: artifact) }.buttonStyle(.plain)
            }
            ForEach(model.files.filter { $0.conversationID == conversationID && source?.excludedFileIDs.contains($0.id) != true }) { file in
                Button { navigation.destination = .file(file.id) } label: { WorkspaceFileRow(file: file) }.buttonStyle(.plain)
            }
        }.task(id: conversationID) { source = try? await model.store?.loadConversation(conversationID) }.navigationTitle("Files in this chat").navigationBarTitleDisplayMode(.inline)
    }
}
