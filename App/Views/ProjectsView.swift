import AssistantCore
import SwiftUI

struct ProjectsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var projects: [ProjectWorkspace] = []
    var body: some View {
        List {
            Section { Text("Keep the goal, decisions and current outputs together. Chats in a topic folder can share one project record.").foregroundStyle(.secondary) }
            ForEach(projects) { project in
                NavigationLink { ProjectDetailView(project: project) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(project.title).font(.headline)
                        Text(project.goal).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        Text("\(project.status.capitalized) · \(project.questions.count) open questions").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 5)
                }
            }
            if projects.isEmpty { ContentUnavailableView("Your work can live here", systemImage: "square.stack.3d.up", description: Text("Ask the assistant to keep a project record for work you plan to revisit.")) }
        }.navigationTitle("Projects")
            .task { projects = (try? await model.store?.projectWorkspaces()) ?? [] }
    }
}
private struct ProjectDetailView: View {
    @EnvironmentObject private var model: AppModel
    @State var project: ProjectWorkspace
    @State private var editing = false
    @State private var error: String?
    var body: some View {
        List {
            Section("Goal") {
                if editing { TextField("Title", text: $project.title); TextField("Goal", text: $project.goal, axis: .vertical).lineLimit(2...6) }
                else { Text(project.goal) }
                Picker("State", selection: $project.status) { ForEach(["active", "waiting", "completed", "paused"], id: \.self) { Text($0.capitalized).tag($0) } }.disabled(!editing)
            }
            if !project.decisions.isEmpty { Section("Decisions") { ForEach(Array(project.decisions.enumerated()), id: \.offset) { _, value in Text(value) } } }
            if !project.questions.isEmpty { Section("Still to work out") { ForEach(Array(project.questions.enumerated()), id: \.offset) { _, value in Label(value, systemImage: "questionmark.circle").foregroundStyle(.secondary) } } }
            Section("Current outputs") {
                ForEach(project.outputIDs, id: \.self) { id in
                    if let file = model.files.first(where: { $0.id == id }) { NavigationLink { WorkspaceFileView(id: id) } label: { WorkspaceFileRow(file: file) } }
                    else if let artifact = model.artifacts.first(where: { $0.id == id }) { NavigationLink { ArtifactDetailView(artifact: artifact) } label: { ArtifactCard(artifact: artifact) } }
                    else { Text("An earlier output is no longer available.").foregroundStyle(.secondary) }
                }
                if project.outputIDs.isEmpty { Text("The assistant can link the authoritative files here as work progresses.").foregroundStyle(.secondary) }
            }
            Section { Text("Updated \(project.updatedAt.formatted(date: .abbreviated, time: .shortened)) · Revision \(project.revision)").font(.caption).foregroundStyle(.secondary) }
            if let error { Text(error).foregroundStyle(.red) }
        }.navigationTitle(project.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(editing ? "Save" : "Edit") {
                if !editing { editing = true; return }
                Task {
                    do { let revision = project.revision; var saved = project; saved.revision += 1; saved.updatedAt = Date(); try await model.store?.saveProjectWorkspace(saved, expectedRevision: revision); project = saved; editing = false; AppFeedback.play(.saved) }
                    catch { self.error = error.localizedDescription }
                }
            } } }
    }
}
