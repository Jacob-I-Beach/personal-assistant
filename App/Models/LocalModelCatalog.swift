import Foundation

struct LocalModelCatalogEntry: Codable, Identifiable, Equatable, Sendable {
    struct File: Codable, Equatable, Sendable { var name: String; var bytes: Int64; var sha256: String? }
    var id: String
    var name: String
    var summary: String
    var revision: String
    var downloadBytes: Int64
    var format: String
    var supportsVision: Bool
    var validation: String
    var files: [File]
    var architecture: String?
    var weightBytes: Int64?
    /// Exact language tensor payload in the pinned multimodal checkpoint.
    /// Present only for packages supported by the LLM factory without vision.
    var textWeightBytes: Int64?
    var estimatedMemoryLowBytes: Int64?
    var estimatedMemoryHighBytes: Int64?
    var mixtureOfExperts: String?
    var sourceURL: URL?
    var downloadSize: String { ByteCountFormatter.string(fromByteCount: downloadBytes, countStyle: .file) }
    var memoryEstimate: String {
        guard let low = estimatedMemoryLowBytes, let high = estimatedMemoryHighBytes else { return "Not estimated" }
        return ByteCountFormatter.string(fromByteCount: low, countStyle: .memory) + "–" + ByteCountFormatter.string(fromByteCount: high, countStyle: .memory)
    }
    static func bundled() throws -> [Self] {
        guard let url = Bundle.main.url(forResource: "ModelCatalog", withExtension: "json") else { return [] }
        let entries = try JSONDecoder().decode([Self].self, from: Data(contentsOf: url))
        guard entries.allSatisfy({ $0.downloadBytes > 0 && $0.downloadBytes == $0.files.reduce(0, { $0 + $1.bytes }) }) else {
            throw CocoaError(.coderInvalidValue)
        }
        return entries
    }
}
