import AssistantCore
import Foundation

enum WorkspaceTools {
    static let connect = NativeTools.definition("connect_workspace", "Present the native folder picker so the user can connect a folder to this chat. Folder access and connected-model sharing require the user's choices; selecting a folder does not grant blanket overwrite permission.", ["reason": "Why this task needs a folder."])
    static let list = NativeTools.definition("list_workspaces", "List connected folders enabled for this conversation and processing location. Does not reveal other folders or bookmarks.", [:])
    static let files = NativeTools.definition("list_files", "List up to 50 immediate entries in an authorized folder. Files have opaque IDs; directory IDs can be used to descend. A cursor is an integer offset.", ["workspace_id": "Connected folder UUID", "folder_id": "Returned directory ID, or empty for the root", "cursor": "Decimal offset, starting at 0"])
    static let read = NativeTools.definition("read_file", "Read a bounded section of a file in a connected folder. Returns extraction limits and a version token. Reviewed edits require a fresh UTF-8 text version; PDFs/Office files are read as extracted text.", ["file_id": "Opaque ID from list_files", "offset": "Character offset, starting at 0"])
    static let create = NativeTools.definition("create_file", "Create and verify a new UTF-8 text, code, CSV or JSON file in a folder with editing enabled. At most 128 KB. Never overwrites different contents. Same-name identical content is treated as an already-completed write. For a PDF use create_pdf then export_artifact.", ["workspace_id": "Connected folder UUID", "folder_id": "Listed subfolder ID, or empty for the root", "filename": "Simple filename, no directories", "content": "Complete UTF-8 contents"])
    static let propose = NativeTools.definition("propose_file_edit", "Prepare a version-checked replacement for a UTF-8 text file up to 128 KB. Does not change the file. Returns a proposal ID for native diff review.", ["file_id": "Opaque file ID", "expected_version": "Version token from read_file", "replacement": "Complete revised text"])
    static let apply = NativeTools.definition("apply_file_edit", "Show the exact proposed diff for user review. Apply only after confirmation and only if original contents still match. A cancelled proposal cannot be retried. Original contents remain in the private edit history.", ["proposal_id": "Proposal ID returned by propose_file_edit"])
    static let export = NativeTools.definition("export_artifact", "Show Save to Files for a permitted Library artifact or document. Waits for the picker callback and reports completed or cancelled. A completed local export does not prove cloud synchronization.", ["kind": "artifact or file", "id": "Artifact/document UUID"])
    static let search = NativeTools.definition("search_files", "Search file names and bounded UTF-8 text previews in an authorized folder. Up to 1,000 entries, 30 matches and 2 MB total text; at most the first 32 KB per text file. Hidden files and links are skipped. Binary formats are matched by name only; use read_file for extraction.", ["workspace_id": "Connected folder UUID", "query": "Search words"])
    static let metadata = NativeTools.definition("get_file_metadata", "Read current size, type and modification time of a scoped file without loading its full content.", ["file_id": "Opaque file ID"])
    static let definitions = [connect, list, files, read, search, metadata, create, propose, apply, export]
    static let names = Set(definitions.map(\.name))
}

extension AppModel {
    func executeWorkspaceTool(_ call: ToolCall, conversationID: UUID, destination: String?) async throws -> ToolResult {
        guard let workspaceService, let store, isRunning, conversation.id == conversationID else { throw CancellationError() }
        let remote = destination != nil
        func result(_ output: JSONValue, succeeded: Bool = true, localOnly: Bool = false) -> ToolResult {
            var value = ToolResult(callID: call.id, name: call.name, succeeded: succeeded, output: output)
            value.containsLocalOnlyContext = localOnly; return value
        }
        func uuid(_ key: String) throws -> UUID {
            guard let raw = call.arguments[key]?.stringValue, let id = UUID(uuidString: raw) else { throw AssistantError.invalidTool("Invalid \(key). Use the identifier returned by the app.") }
            return id
        }
        func checkChatScope(_ id: UUID) throws {
            guard conversation.workspaceIDs.contains(id) else { throw AssistantError.invalidTool("This folder is not connected to this chat. Enable it from Library > Connected folders.") }
        }
        switch call.name {
        case "connect_workspace":
            pickedFolderURL = nil
            let status = try await reviewNativeAction(.init(kind: .folder, title: "Connect folder", detail: String((call.arguments["reason"]?.stringValue ?? "").prefix(500)), arguments: call.arguments))
            guard status == "selected", let url = pickedFolderURL else { return result(.object(["status": .string("cancelled"), "message": .string("The user cancelled folder selection.")]), succeeded: false) }
            pickedFolderURL = nil
            let connection = try await workspaceService.connect(url)
            if remote && !connection.allowsConnectedModels {
                let allowed = try await reviewNativeAction(.init(kind: .approval, title: "Use this folder with \(modelTitle)?", detail: "Allow relevant files from “\(connection.name)” to be read by this connected model when needed for this chat. Editing stays off until you enable it in the folder settings.", arguments: call.arguments))
                if allowed == "approved" { try await workspaceService.setAccess(connection.id, connected: true) }
                else {
                    await refreshWorkspaces()
                    var value = result(.object(["status": .string("connected_local_only"), "message": .string("The folder was connected for on-device use. Sharing with this model was declined. Continue without reading it; do not repeat the permission request.")]))
                    value.authorizedWorkspaceID = connection.id
                    return value
                }
            }
            await refreshWorkspaces()
            var value = result(.object(["workspace_id": .string(connection.id.uuidString), "name": .string(connection.name),
                                        "status": .string("connected"), "editing_enabled": .bool(connection.allowsEdits),
                                        "note": .string("User-selected folder. Actual per-model read and edit permissions are enforced on each operation.")]))
            value.authorizedWorkspaceID = connection.id
            return value
        case "list_workspaces":
            let folders = await workspaceService.connections().filter { conversation.workspaceIDs.contains($0.id) && (!remote || $0.allowsConnectedModels) }
            let pending = await workspaceService.pendingEdits(Set(folders.map(\.id)))
            return result(.object(["folders": .array(folders.map { .object(["workspace_id": .string($0.id.uuidString), "name": .string($0.name), "editing_enabled": .bool($0.allowsEdits)]) }),
                                   "pending_edits": .array(pending.map { .object(["proposal_id": .string($0.id.uuidString), "filename": .string($0.file.relativePath), "status": .string($0.state)]) })]),
                          localOnly: folders.contains { !$0.allowsConnectedModels })
        case "list_files":
            let id = try uuid("workspace_id"); try checkChatScope(id)
            guard let offset = Int(call.arguments["cursor"]?.stringValue ?? "") else { throw AssistantError.invalidTool("Use an integer cursor, starting at 0.") }
            let rawFolder = call.arguments["folder_id"]?.stringValue ?? ""
            guard rawFolder.isEmpty || UUID(uuidString: rawFolder) != nil else { throw AssistantError.invalidTool("Invalid folder ID.") }
            let page = try await workspaceService.list(id, folderID: UUID(uuidString: rawFolder), offset: offset, remote: remote)
            let folders = await workspaceService.connections()
            return result(.object(["entries": .array(page.files.map(Self.folderFileJSON)),
                                   "next_cursor": page.next.map { .string(String($0)) } ?? .null,
                                   "observed_at": .string(ISO8601DateFormatter().string(from: Date()))]),
                          localOnly: folders.first { $0.id == id }?.allowsConnectedModels == false)
        case "read_file":
            let id = try uuid("file_id"), entry = try await workspaceService.fileRecord(id); try checkChatScope(entry.workspaceID)
            guard let offset = Int(call.arguments["offset"]?.stringValue ?? ""), offset >= 0 else { throw AssistantError.invalidTool("Use a non-negative character offset.") }
            let value = try await workspaceService.read(id, remote: remote)
            let (document, _) = try await DocumentImporter.shared.extract(value.data, filename: (entry.relativePath as NSString).lastPathComponent)
            guard offset <= document.text.count else { throw AssistantError.invalidTool("The offset is beyond the extracted text.") }
            let slice = String(document.text.dropFirst(offset).prefix(6000))
            let folders = await workspaceService.connections()
            return result(.object(["file": Self.folderFileJSON(value.file), "text": .string(slice), "next_offset": .number(Double(offset + slice.count)),
                                   "total_characters": .number(Double(document.text.count)), "extraction_note": .string(document.extractionNote),
                                   "version": .string(value.version), "observed_at": .string(ISO8601DateFormatter().string(from: Date())),
                                   "editing_limit": .string("UTF-8 text up to 128 KB. Binary and extracted document formats cannot be replaced by this edit tool.")]),
                          localOnly: folders.first { $0.id == entry.workspaceID }?.allowsConnectedModels == false)
        case "get_file_metadata":
            let id = try uuid("file_id"), entry = try await workspaceService.fileRecord(id); try checkChatScope(entry.workspaceID)
            let current = try await workspaceService.metadata(id, remote: remote), folders = await workspaceService.connections()
            return result(.object(["file": Self.folderFileJSON(current), "observed_at": .string(ISO8601DateFormatter().string(from: Date()))]),
                          localOnly: folders.first { $0.id == entry.workspaceID }?.allowsConnectedModels == false)
        case "search_files":
            let id = try uuid("workspace_id"); try checkChatScope(id)
            let found = try await workspaceService.search(id, query: call.arguments["query"]?.stringValue ?? "", remote: remote)
            let folders = await workspaceService.connections()
            return result(.object(["matches": .array(found.matches.map { .object(["file": Self.folderFileJSON($0.0), "excerpt": .string($0.1)]) }),
                                   "entries_scanned": .number(Double(found.scanned)), "limited": .bool(found.limited),
                                   "scope_note": .string("Filename and bounded text-prefix search, not exhaustive document indexing. Binary documents and hidden files were not searched as text.")]),
                          localOnly: folders.first { $0.id == id }?.allowsConnectedModels == false)
        case "create_file":
            let id = try uuid("workspace_id"); try checkChatScope(id)
            let folder = call.arguments["folder_id"]?.stringValue ?? ""
            guard folder.isEmpty || UUID(uuidString: folder) != nil else { throw AssistantError.invalidTool("Use a listed folder ID or an empty string for the root.") }
            let entry = try await workspaceService.create(id, folderID: UUID(uuidString: folder), filename: call.arguments["filename"]?.stringValue ?? "", content: call.arguments["content"]?.stringValue ?? "", remote: remote)
            return result(.object(["file": Self.folderFileJSON(entry), "status": .string("saved_local"), "verification": .string("Contents read back and matched. Cloud sync was not checked.")]))
        case "propose_file_edit":
            let id = try uuid("file_id"), entry = try await workspaceService.fileRecord(id); try checkChatScope(entry.workspaceID)
            let proposal = try await workspaceService.propose(fileID: id, version: call.arguments["expected_version"]?.stringValue ?? "",
                                                            replacement: call.arguments["replacement"]?.stringValue ?? "", remote: remote)
            return result(.object(["proposal_id": .string(proposal.id.uuidString), "filename": .string(entry.relativePath), "status": .string("awaiting_user"), "changed": .bool(false)]))
        case "apply_file_edit":
            let id = try uuid("proposal_id"), proposal = try await workspaceService.proposal(id, remote: remote)
            try checkChatScope(proposal.file.workspaceID)
            if proposal.state == "cancelled" { return result(.object(["status": .string("cancelled"), "changed": .bool(false)]), succeeded: false) }
            if proposal.state != "applied" {
                let approval = try await reviewNativeAction(.init(kind: .fileEdit, title: "Review file changes", detail: "", arguments: call.arguments, proposal: proposal))
                guard approval == "approved" else {
                    try await workspaceService.cancelProposal(id)
                    return result(.object(["status": .string("cancelled"), "changed": .bool(false)]), succeeded: false)
                }
            }
            let applied = try await workspaceService.apply(id, remote: remote)
            return result(.object(["proposal_id": .string(id.uuidString), "filename": .string(applied.file.relativePath),
                                   "status": .string("saved_local"), "verification": .string("Version checked before writing; replacement read back and matched. Original retained in edit history. Cloud sync not checked.")]))
        case "export_artifact":
            let id = try uuid("id"), url: URL
            if call.arguments["kind"]?.stringValue == "artifact" {
                guard let artifact = try await store.readableArtifacts(conversationID: conversationID, workspace: false, remote: remote).first(where: { $0.id == id }) else { throw AssistantError.invalidTool("That artifact is not available in this chat.") }
                url = try await store.exportArtifact(artifact)
            } else if call.arguments["kind"]?.stringValue == "file" {
                let readable = try await store.readableFiles(attached: conversation.attachedFileIDs, workspace: false, remote: remote, conversationID: conversationID)
                let owned = try await store.workspaceFile(id)
                guard readable.contains(where: { $0.id == id }) || owned.conversationID == conversationID else { throw AssistantError.invalidTool("Attach that document to this chat before exporting it.") }
                url = try await store.workspaceFileURL(id)
            } else { throw AssistantError.invalidTool("Choose artifact or file.") }
            let status = try await reviewNativeAction(.init(kind: .exportFile, title: "Save to Files", detail: "", arguments: call.arguments, fileURL: url))
            return result(.object(["status": .string(status), "filename": .string(url.lastPathComponent),
                                   "message": .string(status == "completed" ? "The document picker confirmed an exported copy. Cloud synchronization was not verified." : "The user cancelled export; no completed export was reported.")]),
                          succeeded: status == "completed")
        default: throw AssistantError.invalidTool("Unknown workspace tool.")
        }
    }
    static func folderFileJSON(_ file: FolderFile) -> JSONValue {
        .object(["file_id": .string(file.id.uuidString), "workspace_id": .string(file.workspaceID.uuidString),
                 "relative_path": .string(file.relativePath), "is_directory": .bool(file.isDirectory),
                 "bytes": .number(Double(file.byteCount)), "modified_at": file.modifiedAt.map { .string(ISO8601DateFormatter().string(from: $0)) } ?? .null])
    }
}
