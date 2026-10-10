import AssistantCore
import Foundation

extension AppModel {
    func refreshWorkspaces() async { connectedFolders = await workspaceService?.connections() ?? [] }
    func connectFolder(_ url: URL) async {
        guard !isRunning, let workspaceService else { return }
        do {
            let connection = try await workspaceService.connect(url)
            conversation.workspaceIDs.insert(connection.id)
            try await store?.save(conversation); await refreshWorkspaces()
        } catch { errorMessage = error.localizedDescription }
    }
    func setFolderEnabled(_ id: UUID, enabled: Bool) async {
        guard !isRunning else { return }
        if enabled { conversation.workspaceIDs.insert(id) } else { conversation.workspaceIDs.remove(id) }
        do { try await store?.save(conversation) } catch { errorMessage = error.localizedDescription }
    }
    func updateFolderAccess(_ folder: FolderConnection, connected: Bool? = nil, edits: Bool? = nil) async {
        guard !isRunning else { return }
        do { try await workspaceService?.setAccess(folder.id, connected: connected, edits: edits); await refreshWorkspaces() }
        catch { errorMessage = error.localizedDescription }
    }
    func disconnectFolder(_ id: UUID) async {
        guard !isRunning else { return }
        do {
            try await workspaceService?.disconnect(id); conversation.workspaceIDs.remove(id)
            try await store?.save(conversation); await refreshWorkspaces()
        } catch { errorMessage = error.localizedDescription }
    }
}
