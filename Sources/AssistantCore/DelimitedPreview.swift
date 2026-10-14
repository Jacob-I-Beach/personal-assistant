import Foundation

/// A bounded literal preview. It never evaluates spreadsheet formulas or markup.
public struct DelimitedPreview: Equatable, Sendable {
    public let rows: [[String]]
    public let truncated: Bool
    public init(_ text: String, delimiter: Character = ",", maximumRows: Int = 100, maximumColumns: Int = 20) {
        let source = Array(text.prefix(100_000)), rowLimit = min(200, max(1, maximumRows)), columnLimit = min(40, max(1, maximumColumns))
        var result: [[String]] = [], row: [String] = [], cell = "", quoted = false, clipped = text.count > source.count, i = 0
        func finishCell() {
            if row.count < columnLimit { row.append(cell) } else { clipped = true }
            cell = ""
        }
        while i < source.count {
            let c = source[i]
            if c == "\"" {
                if quoted && i + 1 < source.count && source[i + 1] == "\"" { if cell.count < 512 { cell.append("\"") } else { clipped = true }; i += 1 }
                else { quoted.toggle() }
            } else if !quoted && c == delimiter { finishCell() }
            else if !quoted && (c == "\n" || c == "\r" || c == "\r\n") {
                finishCell(); result.append(row); row = []
                if c == "\r" && i + 1 < source.count && source[i + 1] == "\n" { i += 1 }
                if result.count >= rowLimit { clipped = clipped || i + 1 < source.count; break }
            } else if cell.count < 512 { cell.append(c) } else { clipped = true }
            i += 1
        }
        if result.count < rowLimit && (!cell.isEmpty || !row.isEmpty) { finishCell(); result.append(row) }
        rows = result; truncated = clipped || quoted
    }
}
