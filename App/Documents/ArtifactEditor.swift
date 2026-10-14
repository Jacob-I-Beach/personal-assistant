import AssistantCore
import Combine
import Foundation

@MainActor
final class ArtifactEditor: ObservableObject {
    @Published private(set) var artifact: ArtifactRecord
    @Published var text = ""
    @Published private(set) var editing = false
    @Published private(set) var loading = true
    @Published private(set) var saving = false
    @Published private(set) var hasDraft = false
    @Published private(set) var draftSaved = false
    @Published private(set) var baseRevision: Int?
    @Published var error: String?
    @Published var notice: String?
    private var store: LocalStore?
    private var autosave: Task<Void, Never>?
    var needsComparison: Bool { hasDraft && baseRevision != artifact.revision }
    var canSave: Bool { editing && !saving && !needsComparison && text != artifact.content }
    init(artifact: ArtifactRecord) { self.artifact = artifact }
    func load(_ store: LocalStore?) async {
        guard let store else { loading = false; error = "The document store is unavailable."; return }
        self.store = store
        do {
            let saved = try await store.artifactRecord(artifact.id)
            artifact = saved
            if let draft = try await store.artifactDraftRecord(id: saved.id) {
                text = draft.text; baseRevision = draft.baseRevision; hasDraft = true; draftSaved = true; editing = true
            } else { text = saved.content; baseRevision = saved.revision }
        } catch { self.error = error.localizedDescription }
        loading = false
    }
    func beginEditing() {
        guard !loading, !saving else { return }
        if !hasDraft { text = artifact.content; baseRevision = artifact.revision }
        editing = true; error = nil; notice = nil
    }
    func useHistoricalText(_ value: String) {
        guard !hasDraft, !saving else { return }
        baseRevision = artifact.revision; text = value; editing = true; changed()
    }
    func changed() {
        guard editing, !saving, !loading, let store else { return }
        hasDraft = true; draftSaved = false; autosave?.cancel()
        let id = artifact.id, value = text, revision = baseRevision
        autosave = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(400)); try Task.checkCancellation()
                try await store.saveArtifactDraft(id: id, text: value, baseRevision: revision)
                guard let self, self.text == value, self.baseRevision == revision else { return }
                self.draftSaved = true
            } catch { if !Task.isCancelled { self?.error = error.localizedDescription } }
        }
    }
    func flush() async {
        autosave?.cancel()
        guard hasDraft, let store, !saving else { return }
        do { try await store.saveArtifactDraft(id: artifact.id, text: text, baseRevision: baseRevision); draftSaved = true }
        catch { self.error = error.localizedDescription }
    }
    func showSaved() async { await flush(); editing = false }
    func discard() async {
        guard let store, !saving else { return }; autosave?.cancel()
        do {
            try await store.saveArtifactDraft(id: artifact.id, text: nil)
            artifact = try await store.artifactRecord(artifact.id)
            editing = false; hasDraft = false; draftSaved = false; text = artifact.content; baseRevision = artifact.revision
            error = nil; notice = "Draft discarded. Saved revision \(artifact.revision) is unchanged."
        } catch { self.error = error.localizedDescription }
    }
    func reviewCurrent() async {
        guard let store else { return }
        do { artifact = try await store.artifactRecord(artifact.id) }
        catch { self.error = error.localizedDescription }
    }
    func useDraftOverCurrentRevision() async {
        // Called only by the explicit comparison action. A later concurrent
        // revision is still rejected by the store's commit check.
        baseRevision = artifact.revision; editing = true; hasDraft = true; error = nil
        await flush()
    }
    func save() async -> (previous: ArtifactRecord, saved: ArtifactRecord)? {
        guard let store, canSave else { return nil }
        autosave?.cancel(); saving = true; error = nil
        defer { saving = false }
        do {
            let previous = artifact
            let saved = try await store.commitArtifactDraft(id: artifact.id, expectedRevision: baseRevision, text: text)
            artifact = saved; baseRevision = saved.revision; editing = false; hasDraft = false; draftSaved = false
            notice = "Revision \(saved.revision) saved."
            return (previous, saved)
        } catch {
            self.error = error.localizedDescription
            if let current = try? await store.artifactRecord(artifact.id) { artifact = current }
            hasDraft = true
            do { try await store.saveArtifactDraft(id: artifact.id, text: text, baseRevision: baseRevision); draftSaved = true }
            catch { self.error = "The revision was not saved, and this draft could not be saved to disk. Keep the editor open and copy your text." }
            return nil
        }
    }
}
