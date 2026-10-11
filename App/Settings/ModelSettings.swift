import Foundation
import AssistantCore

enum ModelChoice: String, CaseIterable, Codable, Identifiable {
    case localMLX, chatGPT, appleOnDevice, appleCloud, openAI, compatibleServer
    var id: String { rawValue }
    var title: String {
        switch self {
        case .localMLX: "Downloaded model"
        case .chatGPT: "ChatGPT"
        case .appleOnDevice: "Apple on this iPhone"
        case .appleCloud: "Apple Private Cloud Compute"
        case .openAI: "OpenAI API"
        case .compatibleServer: "PC / compatible server"
        }
    }
}

struct ModelSettings: Codable, Equatable {
    var choice: ModelChoice = .chatGPT
    var localRepository = "mlx-community/Qwen3.5-4B-4bit"
    var localRevision = "0e7ffd5c629ef7719d4cbc04069232580bfa9d9c"
    var localResponseTokens = 2048
    var openAIModel = ""
    var compatibleBaseURL = ""
    var compatibleModel = ""
    var allowCellularDownloads = false
    var chatGPTModel = ""
    var chatGPTAccountID: String?
    var includeInDeviceBackup = false
    var localOnly = false
    var healthToolsEnabled = false
    var chatGPTWebSearch = true
    var workspaceSearchEnabled = false
    var automaticMemory = true
    var continueInBackground = true
    var taskNotifications = true
    var locationContextEnabled = false
    var weatherFollowsLocation = false
    var weatherPlace: WeatherPlace?
    var speakReplies = false
    var automaticChatTitles = true
    var reasoningByModel: [String: String] = [:]

    enum CodingKeys: String, CodingKey {
        case choice, localRepository, localRevision, localResponseTokens, openAIModel, compatibleBaseURL, compatibleModel
        case allowCellularDownloads, chatGPTModel, chatGPTAccountID, includeInDeviceBackup, localOnly, healthToolsEnabled, chatGPTWebSearch
        case workspaceSearchEnabled, automaticMemory, continueInBackground, taskNotifications, locationContextEnabled, weatherFollowsLocation, weatherPlace, speakReplies, automaticChatTitles, reasoningByModel
    }
    init() {}
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        choice = try values.decodeIfPresent(ModelChoice.self, forKey: .choice) ?? .localMLX
        localRepository = try values.decodeIfPresent(String.self, forKey: .localRepository) ?? localRepository
        localRevision = try values.decodeIfPresent(String.self, forKey: .localRevision) ?? localRevision
        localResponseTokens = try values.decodeIfPresent(Int.self, forKey: .localResponseTokens) ?? localResponseTokens
        openAIModel = try values.decodeIfPresent(String.self, forKey: .openAIModel) ?? ""
        compatibleBaseURL = try values.decodeIfPresent(String.self, forKey: .compatibleBaseURL) ?? ""
        compatibleModel = try values.decodeIfPresent(String.self, forKey: .compatibleModel) ?? ""
        allowCellularDownloads = try values.decodeIfPresent(Bool.self, forKey: .allowCellularDownloads) ?? false
        chatGPTModel = try values.decodeIfPresent(String.self, forKey: .chatGPTModel) ?? ""
        chatGPTAccountID = try values.decodeIfPresent(String.self, forKey: .chatGPTAccountID)
        includeInDeviceBackup = try values.decodeIfPresent(Bool.self, forKey: .includeInDeviceBackup) ?? false
        localOnly = try values.decodeIfPresent(Bool.self, forKey: .localOnly) ?? false
        healthToolsEnabled = try values.decodeIfPresent(Bool.self, forKey: .healthToolsEnabled) ?? false
        chatGPTWebSearch = try values.decodeIfPresent(Bool.self, forKey: .chatGPTWebSearch) ?? true
        workspaceSearchEnabled = try values.decodeIfPresent(Bool.self, forKey: .workspaceSearchEnabled) ?? false
        automaticMemory = try values.decodeIfPresent(Bool.self, forKey: .automaticMemory) ?? true
        continueInBackground = try values.decodeIfPresent(Bool.self, forKey: .continueInBackground) ?? true
        taskNotifications = try values.decodeIfPresent(Bool.self, forKey: .taskNotifications) ?? true
        locationContextEnabled = try values.decodeIfPresent(Bool.self, forKey: .locationContextEnabled) ?? false
        weatherFollowsLocation = try values.decodeIfPresent(Bool.self, forKey: .weatherFollowsLocation) ?? false
        weatherPlace = try values.decodeIfPresent(WeatherPlace.self, forKey: .weatherPlace)
        speakReplies = try values.decodeIfPresent(Bool.self, forKey: .speakReplies) ?? false
        automaticChatTitles = try values.decodeIfPresent(Bool.self, forKey: .automaticChatTitles) ?? true
        reasoningByModel = try values.decodeIfPresent([String: String].self, forKey: .reasoningByModel) ?? [:]
    }

    var endpoint: URL? {
        switch choice {
        case .localMLX, .appleOnDevice, .appleCloud: nil
        case .openAI, .chatGPT: URL(string: "https://api.openai.com/v1")
        case .compatibleServer: URL(string: compatibleBaseURL)
        }
    }
    var credentialAccount: String? { [.openAI, .compatibleServer].contains(choice) ? endpoint.map { "model-server:" + $0.absoluteString } : nil }
    var networkDestination: String? {
        if choice == .appleCloud { return "apple-private-cloud-compute" }
        if choice == .chatGPT { return chatGPTAccountID.map { "chatgpt-account:" + $0 } }
        return endpoint?.absoluteString
    }
}

enum PrivatePaths {
    static func outputs() throws -> URL {
        let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        var name = "Outputs"
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--ui-") }) { name = "Test Outputs" }
        #endif
        var directory = documents.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: directory.path)
        return directory
    }
    static func root() throws -> URL {
        var folder = "PersonalAssistant"
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-empty") { folder = "PersonalAssistant-UITests-Empty" }
        if ProcessInfo.processInfo.arguments.contains("--ui-demo") { folder = "PersonalAssistant-UITests-Demo" }
        if ProcessInfo.processInfo.arguments.contains("--ui-library") { folder = "PersonalAssistant-UITests-Demo" }
        if ProcessInfo.processInfo.arguments.contains("--ui-presentation") { folder = "PersonalAssistant-UITests-Presentation" }
        if ProcessInfo.processInfo.arguments.contains("--ui-streaming") { folder = "PersonalAssistant-UITests-Streaming" }
        if ProcessInfo.processInfo.arguments.contains("--ui-continuity") { folder = "PersonalAssistant-UITests-Continuity" }
        if ProcessInfo.processInfo.arguments.contains("--ui-background") { folder = "PersonalAssistant-UITests-Background" }
        if ProcessInfo.processInfo.arguments.contains("--ui-long-task") { folder = "PersonalAssistant-UITests-LongTask" }
        #endif
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
            .appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var excluded = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try excluded.setResourceValues(values)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: directory.path)
        return directory
    }
    static func configureBackup(root: URL, includeUserData: Bool) throws {
        // Preserve the original private default. Only an explicit preference includes user data in device backups.
        for (url, exclude) in [(root, false), (root.appendingPathComponent("data"), !includeUserData),
                                (root.appendingPathComponent("models"), true), (try outputs(), !includeUserData)] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            var target = url
            var values = URLResourceValues(); values.isExcludedFromBackup = exclude
            try target.setResourceValues(values)
        }
    }
}
