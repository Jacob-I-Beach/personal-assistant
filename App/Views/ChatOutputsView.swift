import AssistantCore
import SwiftUI

struct ChatOutputsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var navigation: ChatNavigation
    let conversationID: UUID
    var body: some View {
        List {
            let documents = model.artifacts.filter { $0.conversationID == conversationID && !model.conversation.excludedArtifactIDs.contains($0.id) }
            let superseded = Set(documents.compactMap(\.previousRevisionID))
            ForEach(documents.filter { !superseded.contains($0.id) }) { artifact in
                Button { navigation.destination = .artifact(artifact.id) } label: { ArtifactCard(artifact: artifact) }.buttonStyle(.plain)
            }
            ForEach(model.files.filter { $0.conversationID == conversationID && !model.conversation.excludedFileIDs.contains($0.id) }) { file in
                Button { navigation.destination = .file(file.id) } label: { WorkspaceFileRow(file: file) }.buttonStyle(.plain)
            }
        }.navigationTitle("Files in this chat").navigationBarTitleDisplayMode(.inline)
    }
}
