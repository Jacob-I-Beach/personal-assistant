import Foundation

public struct LibrarySearchResult: Sendable, Equatable {
    public var fileIDs: Set<UUID>
    public var artifactIDs: Set<UUID>
    public var excerpts: [UUID: String] = [:]
}
public struct LibrarySearchFilter: Sendable, Equatable {
    public var filename: String = ""
    public var fileExtension: String = ""
    public var since: Date?
    public var conversationID: UUID?
    public init() {}
}
extension LocalStore {
    /// Rebuildable local index; triggers share the transaction of every source mutation.
    public func rebuildLibraryIndex() throws {
        try database.transaction {
            for table in ["artifacts", "workspace_files"] {
                for action in ["insert", "update", "delete"] { try database.execute("DROP TRIGGER IF EXISTS library_\(table)_\(action)") }
            }
            try database.execute("DROP TABLE IF EXISTS library_search_v1")
            try createLibraryIndex()
        }
    }
    private func createLibraryIndex() throws {
        try database.execute("CREATE VIRTUAL TABLE library_search_v1 USING fts5(id UNINDEXED,kind UNINDEXED,filename,body,origin UNINDEXED,created UNINDEXED, tokenize='unicode61 remove_diacritics 2')")
        for (table, kind, body) in [("artifacts", "document", "content"), ("workspace_files", "file", "text")] {
            func projection(_ prefix: String) -> String {
                let payload = "CAST(\(prefix)payload AS TEXT)"
                return "\(prefix)id,'\(kind)',json_extract(\(payload),'$.filename'),json_extract(\(payload),'$.\(body)'),json_extract(\(payload),'$.conversationID'),\(prefix)created_at"
            }
            try database.execute("INSERT INTO library_search_v1 SELECT \(projection("")) FROM \(table)")
            try database.execute("CREATE TRIGGER library_\(table)_insert AFTER INSERT ON \(table) BEGIN INSERT INTO library_search_v1 VALUES(\(projection("new."))); END")
            try database.execute("CREATE TRIGGER library_\(table)_update AFTER UPDATE OF payload ON \(table) WHEN old.payload != new.payload BEGIN DELETE FROM library_search_v1 WHERE id=old.id AND kind='\(kind)'; INSERT INTO library_search_v1 VALUES(\(projection("new."))); END")
            try database.execute("CREATE TRIGGER library_\(table)_delete AFTER DELETE ON \(table) BEGIN DELETE FROM library_search_v1 WHERE id=old.id AND kind='\(kind)'; END")
        }
    }
    /// Discovery is not a sharing grant. Per-source model permissions still apply.
    public func searchLibrary(_ query: String, filter: LibrarySearchFilter = .init()) throws -> LibrarySearchResult {
        try Task.checkCancellation()
        if try database.execute("SELECT 1 FROM sqlite_master WHERE name='library_search_v1'").isEmpty { try database.transaction { try createLibraryIndex() } }
        let words = query.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).prefix(20)
        var clauses = ["NOT EXISTS(SELECT 1 FROM artifacts a WHERE json_extract(CAST(a.payload AS TEXT),'$.previousRevisionID')=library_search_v1.id)"]
        var values: [SQLValue] = []
        if !words.isEmpty { clauses.append("library_search_v1 MATCH ?"); values.append(.text(words.map { "\"" + $0 + "\"*" }.joined(separator: " AND "))) }
        if !filter.filename.isEmpty { clauses.append("instr(lower(filename),lower(?))>0"); values.append(.text(filter.filename)) }
        if !filter.fileExtension.isEmpty { clauses.append("lower(substr(filename,-length(?)))=lower(?)"); let suffix = "." + filter.fileExtension; values += [.text(suffix), .text(suffix)] }
        if let date = filter.since { clauses.append("CAST(created AS REAL)>=?"); values.append(.real(date.timeIntervalSince1970)) }
        if let id = filter.conversationID { clauses.append("origin=?"); values.append(.text(id.uuidString)) }
        let rows = try database.execute("SELECT id,kind,\(words.isEmpty ? "substr(body,1,180)" : "snippet(library_search_v1,3,'','', '…',28)") FROM library_search_v1 WHERE \(clauses.joined(separator: " AND ")) ORDER BY \(words.isEmpty ? "CAST(created AS REAL) DESC" : "rank") LIMIT 500", values)
        try Task.checkCancellation()
        var result = LibrarySearchResult(fileIDs: [], artifactIDs: [])
        for row in rows {
            guard let id = row[0].text.flatMap(UUID.init(uuidString:)) else { continue }
            if row[1].text == "file" { result.fileIDs.insert(id) } else { result.artifactIDs.insert(id) }
            result.excerpts[id] = row[2].text ?? ""
        }
        return result
    }
}
