import Foundation

public struct CitationSource: Equatable, Sendable, Identifiable {
    public var citation: WebCitation
    public var numbers: [Int]
    public var id: String { citation.url.absoluteString }
    /// Repeated annotations share a source row while keeping every inline reference number.
    public static func group(_ citations: [WebCitation]) -> [CitationSource] {
        var result: [CitationSource] = [], indexes: [String: Int] = [:]
        for (offset, citation) in citations.enumerated() {
            let key = citation.url.absoluteString
            if let index = indexes[key] { result[index].numbers.append(offset + 1) }
            else {
                indexes[key] = result.count
                result.append(CitationSource(citation: citation, numbers: [offset + 1]))
            }
        }
        return result
    }
}
