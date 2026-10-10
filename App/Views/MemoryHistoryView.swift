import AssistantCore
import SwiftUI

struct MemoryHistoryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var changes: [MemoryChange] = []
    @State private var currentRevisions: [UUID: Int] = [:]
    @State private var error: String?
    @State private var hasMore = true
    @State private var loading = false
    var body: some View {
        List {
            if changes.isEmpty { ContentUnavailableView("No memory changes yet", systemImage: "clock.arrow.circlepath", description: Text("When context is saved, changed or forgotten, its history appears here.")) }
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            ForEach(changes) { change in
                DisclosureGroup {
                    if let before = change.before {
                        VStack(alignment: .leading, spacing: 5) { Text("Before").font(.caption).foregroundStyle(.secondary); Text(before.text).font(.subheadline).textSelection(.enabled) }
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(change.after.status == .forgotten ? "Forgotten context" : "After").font(.caption).foregroundStyle(.secondary)
                        Text(change.after.text).font(.subheadline).textSelection(.enabled)
                        if let quote = change.after.sourceQuote { Text("Source: “\(quote)”").font(.footnote).foregroundStyle(.secondary).textSelection(.enabled) }
                    }
                    if currentRevisions[change.memoryID] == change.after.revision {
                        Button("Undo this change", systemImage: "arrow.uturn.backward") {
                            Task {
                                do { _ = try await model.store?.undoMemoryChange(change.id); error = nil; await refresh() }
                                catch { self.error = error.localizedDescription }
                            }
                        }.font(.subheadline)
                    } else { Text("A newer change exists. Review the latest version to undo it.").font(.caption).foregroundStyle(.secondary) }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(change.after.title).foregroundStyle(.primary)
                        Text(change.action.replacingOccurrences(of: "_", with: " ").capitalized + " · " + (change.actor == "user" ? "You" : change.actor == "app" ? "App" : "Assistant"))
                            .font(.caption).foregroundStyle(.secondary)
                        Text(change.createdAt, style: .date).font(.caption2).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }
            }
            if hasMore { Button("Show more") { Task { await loadMore() } }.disabled(loading) }
        }.navigationTitle("Memory history").task { await refresh() }
    }
    private func refresh() async {
        do {
            let count = max(25, changes.count)
            changes = []
            for offset in stride(from: 0, to: count, by: 25) {
                let page = try await model.store?.memoryChanges(offset: offset, limit: 25) ?? []
                changes += page; hasMore = page.count == 25
                if !hasMore { break }
            }
            var revisions: [UUID: Int] = [:]
            for id in Set(changes.map(\.memoryID)) { revisions[id] = try await model.store?.memory(id)?.revision }
            currentRevisions = revisions
        } catch { self.error = error.localizedDescription }
    }
    private func loadMore() async {
        guard !loading else { return }; loading = true
        defer { loading = false }
        do {
            let page = try await model.store?.memoryChanges(offset: changes.count, limit: 25) ?? []
            changes += page; hasMore = page.count == 25
            for id in Set(page.map(\.memoryID)) { currentRevisions[id] = try await model.store?.memory(id)?.revision }
        } catch { self.error = error.localizedDescription }
    }
}
