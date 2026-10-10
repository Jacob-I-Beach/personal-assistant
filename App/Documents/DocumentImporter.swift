import AssistantCore
import Foundation
import PDFKit
import UniformTypeIdentifiers
import ZIPFoundation

actor DocumentImporter {
    static let shared = DocumentImporter()
    static let maximumBytes = 25 * 1024 * 1024
    private let textLimit = 1_900_000

    func read(_ url: URL) throws -> (WorkspaceFile, Data) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= Self.maximumBytes else {
            throw AssistantError.provider("Choose a file up to 25 MB. Import model folders from Models instead.")
        }
        try WorkspaceFile.validateFilename(url.lastPathComponent)
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= Self.maximumBytes else { throw AssistantError.provider("The file grew beyond the 25 MB import limit.") }
        return try extract(data, filename: url.lastPathComponent)
    }
    func extract(_ data: Data, filename: String) throws -> (WorkspaceFile, Data) {
        try WorkspaceFile.validateFilename(filename)
        guard data.count <= Self.maximumBytes else { throw AssistantError.provider("The file exceeds the 25 MB limit.") }
        let ext = (filename as NSString).pathExtension.lowercased()
        let text: String, note: String
        switch ext {
        case "pdf":
            guard let document = PDFDocument(data: data), !document.isLocked else { throw AssistantError.provider("This PDF could not be opened, or needs a password. Unlock a copy before importing.") }
            var parts: [String] = [], characters = 0, missing = 0
            for index in 0..<min(document.pageCount, 200) {
                try Task.checkCancellation()
                let page = document.page(at: index)?.string ?? ""
                if page.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { missing += 1 }
                parts.append("[Page \(index + 1)]\n\(page)"); characters += page.utf8.count
                if characters > textLimit { break }
            }
            text = bounded(parts.joined(separator: "\n\n"))
            note = "PDF text extraction; page images, diagrams and layout are not included. Read \(parts.count) of \(document.pageCount) pages; \(missing) had no extractable text. Scanned pages require an image capture for vision."
        case "docx", "pptx", "xlsx":
            (text, note) = try office(data, extension: ext)
        default:
            let allowed = ["txt", "md", "markdown", "csv", "tsv", "json", "jsonl", "xml", "html", "htm", "css", "js", "ts", "py", "swift", "yaml", "yml", "log", "sql", "c", "h", "cpp", "rs", "sh", "toml", "ics", "vcf", "svg"]
            if allowed.contains(ext), let decoded = String(data: data, encoding: .utf8) ?? (data.starts(with: [0xff, 0xfe]) || data.starts(with: [0xfe, 0xff]) ? String(data: data, encoding: .utf16) : nil), !decoded.contains("\0") {
                text = bounded(decoded)
                note = data.count > textLimit ? "Text extraction truncated to the first 1.9 MB. Original file retained." : "Plain text; code, markup, formulas and embedded links were not executed."
            } else {
                text = ""
                note = "Original file retained for preview and sharing. This format has no text reader in this build; the assistant cannot inspect its binary contents."
            }
        }
        return (WorkspaceFile(filename: filename, mediaType: UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream",
            byteCount: data.count, text: text, extractionNote: note), data)
    }
    private func bounded(_ text: String) -> String {
        guard text.utf8.count > textLimit else { return text }
        return String(decoding: text.utf8.prefix(textLimit - 4), as: UTF8.self)
    }
    private func office(_ data: Data, extension ext: String) throws -> (String, String) {
        let archive = try Archive(data: data, accessMode: .read)
        let entries = Array(archive)
        guard entries.count <= 4000, entries.allSatisfy({ $0.uncompressedSize <= 50 * 1024 * 1024 }) else { throw AssistantError.provider("This Office document is too large to unpack safely on the phone.") }
        var expanded: UInt64 = 0
        func xml(_ path: String, shared: [String] = [], spreadsheet: Bool = false) throws -> OfficeXML {
            guard let entry = archive[path], entry.type == .file, entry.uncompressedSize <= 8 * 1024 * 1024 else { throw AssistantError.provider("A document part is missing or too large to read.") }
            expanded += entry.uncompressedSize
            guard expanded <= 24 * 1024 * 1024 else { throw AssistantError.provider("The document's extracted XML exceeds the phone reading limit.") }
            var bytes = Data()
            let checksum = try archive.extract(entry, bufferSize: 32 * 1024) { chunk in
                guard bytes.count + chunk.count <= 8 * 1024 * 1024 else { throw AssistantError.provider("An archive part exceeds the extraction limit.") }
                bytes.append(chunk)
            }
            guard checksum == entry.checksum, UInt64(bytes.count) == entry.uncompressedSize else { throw AssistantError.provider("An Office document part failed its archive checksum or size check. Import an intact copy.") }
            // OOXML does not need DTDs or external entities. Reject declarations before parsing.
            let decoded = bytes.starts(with: [0xff, 0xfe]) || bytes.starts(with: [0xfe, 0xff])
                ? String(data: bytes, encoding: .utf16) : String(data: bytes, encoding: .utf8)
            guard let decoded, !decoded.contains("\0") else { throw AssistantError.provider("The Office XML text encoding is unsupported.") }
            let prefix = decoded.uppercased()
            guard !prefix.contains("<!DOCTYPE"), !prefix.contains("<!ENTITY") else { throw AssistantError.provider("Document XML entity declarations are not supported.") }
            let delegate = OfficeXML(shared: shared, spreadsheet: spreadsheet)
            let parser = XMLParser(data: bytes); parser.shouldResolveExternalEntities = false; parser.delegate = delegate
            guard parser.parse() else { throw AssistantError.provider("The document contains unreadable XML.") }
            return delegate
        }
        if ext == "docx" {
            let body = try xml("word/document.xml")
            return (bounded(body.text), "Word body text; formatting, headers, footnotes, embedded images and tracked-change semantics are not preserved. Original DOCX retained.")
        }
        if ext == "pptx" {
            let slides = entries.map(\.path).filter { $0.hasPrefix("ppt/slides/slide") && $0.hasSuffix(".xml") && !$0.contains("/_rels/") }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            var parts: [String] = []
            for (index, path) in slides.prefix(200).enumerated() { parts.append("[Slide \(index + 1)]\n" + (try xml(path).text)) }
            return (bounded(parts.joined(separator: "\n\n")), "Slide text only, up to 200 slides. Charts, speaker notes, diagrams, animations and layout are not analyzed.")
        }
        let shared = archive["xl/sharedStrings.xml"] == nil ? [] : try xml("xl/sharedStrings.xml").strings
        let sheets = entries.map(\.path).filter { $0.hasPrefix("xl/worksheets/sheet") && $0.hasSuffix(".xml") && !$0.contains("/_rels/") }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        var parts: [String] = []
        for path in sheets.prefix(50) { parts.append("[\(path)]\n" + (try xml(path, shared: shared, spreadsheet: true).text)) }
        return (bounded(parts.joined(separator: "\n\n")), "Worksheet cell addresses and stored values, up to 50 sheets. Formula results are cached and may be stale; formulas are not recalculated. Number/date formatting, charts and workbook relationships are not interpreted.")
    }
}

private final class OfficeXML: NSObject, XMLParserDelegate {
    var text = "", strings: [String] = []
    private let shared: [String], spreadsheet: Bool
    private var stack: [String] = [], sharedString = "", cellValue = "", cellType = "", cellID = "", formula = ""
    init(shared: [String], spreadsheet: Bool) { self.shared = shared; self.spreadsheet = spreadsheet }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName; stack.append(name)
        if name == "si" { sharedString = "" }
        if name == "c" { cellValue = ""; formula = ""; cellType = attributes["t"] ?? ""; cellID = attributes["r"] ?? "?" }
        if name == "tab" && !spreadsheet { text += "\t" }
        if name == "br" && !spreadsheet { text += "\n" }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if text.utf8.count > 1_900_000 { return }
        if stack.contains("si"), stack.last == "t" { sharedString += string }
        if spreadsheet {
            if stack.last == "v" || stack.last == "t" { cellValue += string }
            if stack.last == "f" { formula += string }
        } else if stack.last == "t" { text += string }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        let name = stack.last ?? ""
        if name == "si" { strings.append(sharedString) }
        if spreadsheet && name == "c" {
            let value = cellType == "s" ? Int(cellValue).flatMap { shared.indices.contains($0) ? shared[$0] : nil } ?? "[missing shared string]" : cellValue
            if text.utf8.count <= 1_900_000 { text += "\(cellID): \(value)" + (formula.isEmpty ? "" : " [cached; formula: \(formula)]") + "\n" }
        } else if !spreadsheet && ["p", "tr"].contains(name) { text += "\n" }
        else if !spreadsheet && name == "tc" { text += "\t" }
        if !stack.isEmpty { stack.removeLast() }
    }
}
