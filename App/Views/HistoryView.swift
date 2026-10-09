import AssistantCore
import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var matches: [HistoryMatch] = []
    var body: some View {
        NavigationStack {
            List {
                Button("New conversation", systemImage: "square.and.pencil") { model.newConversation(); dismiss() }
                if query.isEmpty {
                    ForEach(model.histories) { conversation in
                        Button {
                            Task { await model.selectConversation(conversation); dismiss() }
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(conversation.title).foregroundStyle(.primary).lineLimit(2)
                                Text(conversation.updatedAt, style: .relative).font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 4)
                        }
                    }
                } else {
                    ForEach(matches) { match in
                        Button {
                            if let summary = model.histories.first(where: { $0.id == match.conversationID }) {
                                Task { await model.selectConversation(summary); dismiss() }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(match.title).font(.headline).foregroundStyle(.primary)
                                Text(match.excerpt).font(.subheadline).foregroundStyle(.secondary).lineLimit(4)
                            }.padding(.vertical, 4)
                        }
                    }
                }
            }
            .overlay {
                if !query.isEmpty && matches.isEmpty { ContentUnavailableView.search(text: query) }
                else if query.isEmpty && model.histories.isEmpty { ContentUnavailableView("Your conversations live here", systemImage: "bubble.left.and.bubble.right", description: Text("Start a conversation and return to it whenever you need.")) }
            }
            .searchable(text: $query, prompt: "Search your conversations")
            .navigationTitle("History")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task(id: query) {
                guard !query.isEmpty else { matches = []; return }
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                let result = await model.searchHistory(query)
                if !Task.isCancelled { matches = result }
            }
        }
    }
}
