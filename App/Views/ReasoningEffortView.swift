import AssistantCore
import SwiftUI

struct ReasoningEffortView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.supportedReasoningEfforts) { effort in
                        Button {
                            model.chooseReasoningEffort(effort); dismiss()
                        } label: {
                            HStack(spacing: 14) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(effort.title).font(.body.weight(.medium)).foregroundStyle(.primary)
                                    Text(effort.summary).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if model.selectedReasoningEffort == effort { Image(systemName: "checkmark").fontWeight(.semibold) }
                            }.padding(.vertical, 5).contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(model.isRunning)
                    }
                } footer: { Text("Applies to new replies from \(model.modelTitle). Higher effort can improve difficult work, but does not guarantee a better answer. Your choice is saved for this model.") }
            }
            .navigationTitle("Thinking effort").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.presentationDetents([.medium, .large])
    }
}
