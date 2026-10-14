import AssistantCore
import SwiftUI

struct TaskActivityView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var report: JSONValue?
    @State private var note: String?
    @State private var work: WorkTurn?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let work {
                        Text(work.goal).font(.title2.weight(.semibold))
                        Label(model.pendingQuestions.contains(where: { $0.turnID == work.id }) ? "Waiting for your answer" : work.phase == .running ? (model.activity ?? "Working on your request") : work.phase == .completed ? "Response ready" : work.phase == .cancelled ? "Stopped by you" : work.phase == .superseded ? "Continued in a later request" : "Saved work needs attention", systemImage: work.phase == .completed ? "checkmark.circle" : "list.bullet.rectangle").font(.subheadline)
                        if let reason = work.reason { Text(reason).font(.subheadline).foregroundStyle(.secondary) }
                        if !work.plan.isEmpty {
                            ForEach(Array(work.plan.enumerated()), id: \.offset) { _, step in
                                Label(step["title"]?.stringValue ?? "Recorded step", systemImage: step["status"] == .string("completed") ? "checkmark.circle" : "circle").font(.subheadline)
                            }
                        }
                        Button("Open response") { dismiss() }.buttonStyle(.bordered)
                    }
                    if let report {
                        DisclosureGroup("Technical details") { ReceiptDetailView(nodes: ReceiptDetails.nodes(report)) }
                        Text("The diagnostic report excludes messages, files, location and account details.").font(.caption).foregroundStyle(.secondary)
                        if let text = try? report.jsonString() {
                            ShareLink(item: text) { Label("Share diagnostic report", systemImage: "square.and.arrow.up") }.buttonStyle(.bordered)
                        }
                    } else { Text(note ?? "Reading the saved record…").foregroundStyle(.secondary) }
                }.padding(24)
            }.navigationTitle("Task activity").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .task(id: "\(model.conversation.messages.last(where: \.isRequest)?.id.uuidString ?? "none")-\(model.isRunning)") {
                    guard let id = model.conversation.messages.last(where: \.isRequest)?.id else { note = "Send a request to start a task record."; return }
                    do {
                        work = try await model.store?.workTurn(id)
                        var fields = try await model.store?.taskDiagnostics(id).objectValue ?? [:]
                        fields["background_processing"] = ResponseCompletionWindow.diagnostic(for: id)
                        report = .object(fields)
                    }
                    catch { note = "This older conversation has no task record. New requests record their progress here." }
                }
        }
    }
}
