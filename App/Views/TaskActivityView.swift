import AssistantCore
import SwiftUI

struct TaskActivityView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var report: JSONValue?
    @State private var note: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("What happened in this task").font(.title2.weight(.semibold))
                    Text("See recorded progress and share a diagnostic report when something feels broken. The report leaves out your messages, files, location and account details.").font(.subheadline).foregroundStyle(.secondary)
                    if let report {
                        ReceiptDetailView(nodes: ReceiptDetails.nodes(report))
                        if let text = try? report.jsonString() {
                            ShareLink(item: text) { Label("Share diagnostic report", systemImage: "square.and.arrow.up") }.buttonStyle(.bordered)
                        }
                    } else { Text(note ?? "Reading the saved record…").foregroundStyle(.secondary) }
                }.padding(24)
            }.navigationTitle("Task activity").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .task {
                    guard let id = model.conversation.messages.last(where: { $0.role == .user })?.id else { note = "Send a request to start a task record."; return }
                    do { report = try await model.store?.taskDiagnostics(id) }
                    catch { note = "This older conversation has no task record. New requests record their progress here." }
                }
        }
    }
}
