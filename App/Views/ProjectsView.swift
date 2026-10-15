import AssistantCore
import SwiftUI

struct ProjectsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var projects: [ProjectWorkspace] = []
    @State private var creating = false
    var body: some View {
        List {
            Section { Text("Keep a goal, decisions and current outputs together. A project uses its existing chat or topic folder.").foregroundStyle(.secondary) }
            ForEach(projects) { project in
                NavigationLink { ProjectDetailView(project: project) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(project.title).font(.headline)
                        if project.needsContextRebuild == true { Label("Review after chat edit", systemImage: "arrow.trianglehead.clockwise").font(.caption).foregroundStyle(.secondary) }
                        if !project.goal.isEmpty { Text(project.goal).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
                        Text("\(project.status.capitalized) · \(project.questions.count) open questions").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 5)
                }
            }
            if projects.isEmpty { ContentUnavailableView("Your work can live here", systemImage: "square.stack.3d.up", description: Text("Create a project or save the current chat to one.")) }
            Button("Create project", systemImage: "plus") { creating = true }.disabled(model.isRunning)
            if model.isRunning { Text("You can read projects while a reply runs. Finish or stop it before creating or continuing another project.").font(.caption).foregroundStyle(.secondary) }
        }.navigationTitle("Projects")
            .task { await refresh() }
            .sheet(isPresented: $creating, onDismiss: { Task { await refresh() } }) { ProjectCreator() }
    }
    private func refresh() async { projects = (try? await model.store?.projectWorkspaces()) ?? [] }
}
private struct ProjectCreator: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var goal = ""
    @State private var useCurrent = true
    @State private var owner: UUID?
    @State private var saving = false
    @State private var failure: String?
    var body: some View {
        NavigationStack {
            Form {
                TextField("Project title", text: $title).accessibilityIdentifier("project-title")
                TextField("Goal, optional", text: $goal, axis: .vertical).lineLimit(3...6)
                Toggle("Save current chat to this project", isOn: $useCurrent)
                Text(useCurrent ? "Uses this chat's existing identity and folder. Your draft stays in place." : "Creates an empty project conversation. Nothing is sent to a model.").font(.caption).foregroundStyle(.secondary)
                if let failure { Text(failure).foregroundStyle(.secondary) }
            }.navigationTitle("Create project").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Create") { Task { await save() } }.disabled(saving || model.isRunning || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }.onAppear { owner = model.conversation.id }
        }
    }
    private func save() async {
        guard let store = model.store, !model.isRunning, !saving else { return }; saving = true; defer { saving = false }
        do {
            if useCurrent {
                guard model.conversation.id == owner else { throw AssistantError.provider("The chat changed. Reopen Create project from the intended chat.") }
                try await store.save(model.conversation)
            }
            _ = try await store.createProject(title: title, goal: goal, conversationID: useCurrent ? owner : nil)
            await model.refresh(); dismiss()
        } catch { failure = error.localizedDescription }
    }
}
private struct ProjectDetailView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var navigation: ChatNavigation
    @State var project: ProjectWorkspace
    @State private var original: ProjectWorkspace?
    @State private var editing = false
    @State private var failure: String?
    @State private var decisions = ""
    @State private var questions = ""
    @State private var discard = false
    var body: some View {
        List {
            Section {
                Button("Continue project", systemImage: "arrow.turn.up.right") { Task { await continueProject() } }.disabled(model.isRunning || editing)
                if model.isRunning { Text("Finish or stop the active response before continuing here.").font(.caption).foregroundStyle(.secondary) }
                if project.needsContextRebuild == true { Text("This record predates a chat edit. Review it before using its assumptions again.").font(.caption).foregroundStyle(.secondary) }
            }
            Section("Goal") {
                if editing { TextField("Title", text: $project.title); TextField("Goal", text: $project.goal, axis: .vertical).lineLimit(2...6) }
                else { Text(project.goal.isEmpty ? "Add a goal when you know what you want to achieve." : project.goal) }
                Picker("State", selection: $project.status) { ForEach(["active", "waiting", "completed", "paused"], id: \.self) { Text($0.capitalized).tag($0) } }.disabled(!editing)
            }
            Section("Current outputs") {
                ForEach(project.outputIDs, id: \.self) { id in
                    if let file = model.files.first(where: { $0.id == id }) { NavigationLink { WorkspaceFileView(id: id) } label: { WorkspaceFileRow(file: file) } }
                    else if let artifact = model.artifacts.first(where: { $0.id == id }) { NavigationLink { ArtifactDetailView(artifact: artifact) } label: { ArtifactCard(artifact: artifact) } }
                    else { Text("An earlier output is no longer available.").foregroundStyle(.secondary) }
                }
                if project.outputIDs.isEmpty { Text("Link authoritative documents as the work progresses.").foregroundStyle(.secondary) }
                if editing {
                    ForEach(model.artifacts.filter { $0.conversationID == project.sourceConversationID }) { artifact in
                        Toggle(artifact.filename, isOn: Binding(get: { project.outputIDs.contains(artifact.id) }, set: { value in if value { if !project.outputIDs.contains(artifact.id) { project.outputIDs.append(artifact.id) } } else { project.outputIDs.removeAll { $0 == artifact.id } } }))
                    }
                }
            }
            Section("Open questions") { if editing { TextField("One question per line", text: $questions, axis: .vertical).lineLimit(3...10) } else { ForEach(Array(project.questions.enumerated()), id: \.offset) { _, value in Text(value) }; if project.questions.isEmpty { Text("No open questions recorded.").foregroundStyle(.secondary) } } }
            Section("Decisions") { if editing { TextField("One decision per line", text: $decisions, axis: .vertical).lineLimit(3...10) } else { ForEach(Array(project.decisions.enumerated()), id: \.offset) { _, value in Text(value) } } }
            Section { Text("Updated \(project.updatedAt.formatted(date: .abbreviated, time: .shortened)) · Revision \(project.revision)").font(.caption).foregroundStyle(.secondary) }
            if let failure { Text(failure).foregroundStyle(.secondary) }
        }.navigationTitle(project.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button(editing ? "Save" : "Edit") {
                    if !editing { original = project; decisions = project.decisions.joined(separator: "\n"); questions = project.questions.joined(separator: "\n"); editing = true }
                    else { Task { await save() } }
                }.disabled(model.isRunning) }
                if editing { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if project != original || decisions != original?.decisions.joined(separator: "\n") || questions != original?.questions.joined(separator: "\n") { discard = true } else { editing = false } } } }
            }
            .confirmationDialog("Discard project changes?", isPresented: $discard) { Button("Discard changes", role: .destructive) { if let original { project = original }; editing = false }; Button("Keep editing", role: .cancel) {} }
    }
    private func continueProject() async {
        guard !model.isRunning, let summary = model.histories.first(where: { $0.id == project.sourceConversationID }) else { failure = "The source chat is unavailable."; return }
        await model.selectConversation(summary)
        guard model.conversation.id == project.sourceConversationID, !model.isRunning else { return }
        let reference = ContextReference(kind: .project, sourceID: project.id.uuidString, title: project.title, conversationID: model.conversation.id, revision: project.revision, localOnly: project.containsLocalOnlyContext, health: project.containsHealthData)
        navigation.compose(ContextualDraftProposal(reference: reference, prompt: "Continue this project from its current goal, outputs and open questions."), afterDismissal: true)
    }
    private func save() async {
        do {
            let revision = project.revision; var saved = project
            saved.decisions = decisions.split(separator: "\n").map(String.init); saved.questions = questions.split(separator: "\n").map(String.init)
            saved.revision += 1; saved.updatedAt = Date(); saved.lastMutationWasUserEdit = true; saved.lastMutationCallID = nil; saved.needsContextRebuild = nil
            saved.containsLocalOnlyContext = saved.containsLocalOnlyContext || model.artifacts.contains { saved.outputIDs.contains($0.id) && $0.containsLocalOnlyContext }
            saved.containsHealthData = saved.containsHealthData || model.artifacts.contains { saved.outputIDs.contains($0.id) && $0.containsHealthData }
            try await model.store?.saveProjectWorkspace(saved, expectedRevision: revision); project = saved; editing = false; AppFeedback.play(.saved)
        } catch { failure = error.localizedDescription }
    }
}
