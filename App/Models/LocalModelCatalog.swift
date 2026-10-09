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
    var downloadSize: String { ByteCountFormatter.string(fromByteCount: downloadBytes, countStyle: .file) }
    static func bundled() throws -> [Self] {
        guard let url = Bundle.main.url(forResource: "ModelCatalog", withExtension: "json") else { return [] }
        return try JSONDecoder().decode([Self].self, from: Data(contentsOf: url))
    }
}
