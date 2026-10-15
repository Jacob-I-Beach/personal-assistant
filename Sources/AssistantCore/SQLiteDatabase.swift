import CSQLite
import Foundation

enum SQLValue: Sendable {
    case text(String), blob(Data), integer(Int64), real(Double), null
    var text: String? { if case .text(let value) = self { value } else { nil } }
    var data: Data? { if case .blob(let value) = self { value } else { nil } }
    var number: Double? {
        switch self { case .integer(let value): Double(value); case .real(let value): value; default: nil }
    }
}

/// Owned by LocalStore. All use after construction is serialized by that actor.
final class SQLiteDatabase: @unchecked Sendable {
    private let handle: OpaquePointer
    private(set) var mutationVersion: UInt64 = 0
    init(url: URL) throws {
        var pointer: OpaquePointer?
        let status = sqlite3_open_v2(url.path, &pointer, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard status == SQLITE_OK, let pointer else {
            if let pointer { sqlite3_close_v2(pointer) }
            throw AssistantError.provider("Conversation storage could not be opened (\(status)).")
        }
        handle = pointer
        sqlite3_busy_timeout(pointer, 5_000)
        try execute("PRAGMA foreign_keys = ON")
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA synchronous = FULL")
    }
    deinit { sqlite3_close_v2(handle) }

    @discardableResult
    func execute(_ sql: String, _ parameters: [SQLValue] = []) throws -> [[SQLValue]] {
        // Journal/index writes are independent of transcript payloads. A failed
        // transcript write still invalidates the cache, as does its later rollback.
        let command = sql.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let writes = ["INSERT", "UPDATE", "DELETE", "REPLACE", "DROP", "ALTER"].contains { command.hasPrefix($0) }
        if writes && (command.contains("MESSAGES") || command.contains("CONVERSATIONS")) { mutationVersion &+= 1 }
        var statement: OpaquePointer?
        let status = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard status == SQLITE_OK, let statement else { throw failure(status) }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_bind_parameter_count(statement) == Int32(parameters.count) else { throw failure(SQLITE_MISUSE) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in parameters.enumerated() {
            let position = Int32(index + 1)
            let result: Int32
            switch value {
            case .text(let string): result = string.withCString { sqlite3_bind_text(statement, position, $0, Int32(string.utf8.count), transient) }
            case .blob(let data): result = data.withUnsafeBytes { sqlite3_bind_blob(statement, position, $0.baseAddress, Int32(data.count), transient) }
            case .integer(let integer): result = sqlite3_bind_int64(statement, position, integer)
            case .real(let double): result = sqlite3_bind_double(statement, position, double)
            case .null: result = sqlite3_bind_null(statement, position)
            }
            guard result == SQLITE_OK else { throw failure(result) }
        }
        var rows: [[SQLValue]] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return rows }
            guard result == SQLITE_ROW else { throw failure(result) }
            rows.append((0..<sqlite3_column_count(statement)).map { column in
                switch sqlite3_column_type(statement, column) {
                case SQLITE_TEXT:
                    guard let pointer = sqlite3_column_text(statement, column) else { return .text("") }
                    return .text(String(decoding: UnsafeBufferPointer(start: pointer, count: Int(sqlite3_column_bytes(statement, column))), as: UTF8.self))
                case SQLITE_BLOB:
                    guard let pointer = sqlite3_column_blob(statement, column) else { return .blob(Data()) }
                    return .blob(Data(bytes: pointer, count: Int(sqlite3_column_bytes(statement, column))))
                case SQLITE_INTEGER: return .integer(sqlite3_column_int64(statement, column))
                case SQLITE_FLOAT: return .real(sqlite3_column_double(statement, column))
                default: return .null
                }
            })
        }
    }
    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            _ = try? execute("ROLLBACK")
            throw error
        }
    }
    private func failure(_ code: Int32) -> AssistantError {
        .provider("Conversation storage failed (\(code)). Existing data has been preserved.")
    }
}
