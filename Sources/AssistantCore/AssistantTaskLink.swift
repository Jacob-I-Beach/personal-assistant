import Foundation

public enum AssistantTaskLink: Equatable, Sendable {
    case inbox
    case chat(conversationID: UUID, jobID: UUID?, serverID: String?)

    public init?(_ url: URL) {
        guard url.scheme?.lowercased() == "personalassistant", url.user == nil, url.password == nil,
              url.port == nil, url.fragment == nil, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        if url.host == "notifications", url.path.isEmpty, components.queryItems == nil { self = .inbox; return }
        guard url.host == "task", url.path.split(separator: "/").count == 1,
              let conversation = UUID(uuidString: url.lastPathComponent) else { return nil }
        let items = components.queryItems ?? []
        guard Set(items.map(\.name)).count == items.count, items.allSatisfy({ ["job", "server"].contains($0.name) && $0.value != nil }) else { return nil }
        let rawJob = items.first(where: { $0.name == "job" })?.value
        let rawServer = items.first(where: { $0.name == "server" })?.value
        guard rawJob == nil || rawJob.flatMap(UUID.init(uuidString:)) != nil else { return nil }
        guard (rawJob == nil) == (rawServer == nil), rawServer.map({ !$0.isEmpty && $0.count <= 64 && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") } }) ?? true else { return nil }
        self = .chat(conversationID: conversation, jobID: rawJob.flatMap(UUID.init(uuidString:)), serverID: rawServer)
    }
}
