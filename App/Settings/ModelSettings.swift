import Foundation

enum ModelChoice: String, CaseIterable, Codable, Identifiable {
    case localMLX, openAI, compatibleServer
    var id: String { rawValue }
    var title: String {
        switch self {
        case .localMLX: "Downloaded model"
        case .openAI: "OpenAI API"
        case .compatibleServer: "PC / compatible server"
        }
    }
}

struct ModelSettings: Codable, Equatable {
    var choice: ModelChoice = .localMLX
    var localRepository = "mlx-community/Qwen3.5-4B-4bit"
    var localRevision = "0e7ffd5c629ef7719d4cbc04069232580bfa9d9c"
    var localResponseTokens = 2048
    var openAIModel = ""
    var compatibleBaseURL = ""
    var compatibleModel = ""
    var allowCellularDownloads = false

    var endpoint: URL? {
        switch choice {
        case .localMLX: nil
        case .openAI: URL(string: "https://api.openai.com/v1")
        case .compatibleServer: URL(string: compatibleBaseURL)
        }
    }
    var credentialAccount: String? { endpoint.map { "model-server:" + $0.absoluteString } }
}

enum PrivatePaths {
    static func root() throws -> URL {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
            .appendingPathComponent("PersonalAssistant", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var excluded = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try excluded.setResourceValues(values)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: directory.path)
        return directory
    }
}
