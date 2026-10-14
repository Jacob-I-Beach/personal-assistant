import Foundation

public struct LibrarySearchResult: Sendable, Equatable {
    public var fileIDs: Set<UUID>
    public var artifactIDs: Set<UUID>
}
extension LocalStore {
    /// UI-only, on-device discovery. A result is not permission to send its
    /// contents to a model; source-specific checks still run at attachment/use.
    public func searchLibrary(_ query: String) throws -> LibrarySearchResult {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let files = try workspaceFiles(), documents = try artifacts()
        let superseded = Set(documents.compactMap(\.previousRevisionID))
        return LibrarySearchResult(
            fileIDs: Set(files.filter { query.isEmpty || $0.filename.localizedCaseInsensitiveContains(query) || $0.text.localizedCaseInsensitiveContains(query) }.map(\.id)),
            artifactIDs: Set(documents.filter { !superseded.contains($0.id) && (query.isEmpty || $0.filename.localizedCaseInsensitiveContains(query) || $0.content.localizedCaseInsensitiveContains(query)) }.map(\.id)))
    }
}
