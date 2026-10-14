import Foundation

public struct AccountModelCatalog: Codable, Equatable, Sendable {
    public var owner: String
    public var models: [ChatGPTModel]
    public var updatedAt: Date
    public init(owner: String, models: [ChatGPTModel], updatedAt: Date = Date()) {
        self.owner = owner; self.models = models; self.updatedAt = updatedAt
    }
}

/// An authenticated account is not proof of model-service availability. A
/// transient failure preserves only that same account's verified choices.
public struct ModelCatalogState: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case idle, refreshing, ready, stale, unavailable }
    public var owner: String?
    public var models: [ChatGPTModel] = []
    public var phase: Phase = .idle
    public var issue: String?
    public var updatedAt: Date?
    public init() {}
    public mutating func begin(owner: String, saved: AccountModelCatalog?) {
        if self.owner != owner { self = .init(); self.owner = owner }
        if models.isEmpty, let saved, saved.owner == owner { models = saved.models; updatedAt = saved.updatedAt }
        phase = .refreshing; issue = nil
    }
    public mutating func receive(_ value: AccountModelCatalog, staleReason: String? = nil) {
        guard owner == value.owner else { return }
        models = value.models; updatedAt = value.updatedAt; issue = staleReason
        phase = staleReason == nil ? .ready : (models.isEmpty ? .unavailable : .stale)
    }
    public mutating func failed(owner: String, message: String) {
        guard self.owner == owner else { return }
        issue = message; phase = models.isEmpty ? .unavailable : .stale
    }
    public var detail: String {
        switch phase {
        case .idle: "Model availability has not been checked."
        case .refreshing: "Refreshing model choices…"
        case .ready: models.isEmpty ? "No models were returned for this account." : "Model choices are up to date."
        case .stale: "Showing saved model choices. " + (issue ?? "Current availability could not be checked.")
        case .unavailable: issue ?? "The model list could not be loaded."
        }
    }
    public static func computerObservation(_ payload: JSONValue, profileID: String, owner: String) throws -> ModelCatalogState {
        guard payload["profile_id"] == .string(profileID) else { throw AssistantError.provider("The computer account changed. Check the existing connection before loading its models.") }
        var result = ModelCatalogState(); result.begin(owner: owner, saved: nil)
        let models = try ChatGPTModel.catalog(from: JSONEncoder().encode(payload))
        let state = payload["catalog"]?["state"]?.stringValue
        guard ["ready", "stale", "unavailable"].contains(state ?? "") else { throw AssistantError.provider("The computer returned no recognized model-availability state. Your account is kept.") }
        let issue = payload["catalog"]?["error"]?.stringValue ?? "Current model availability could not be checked. Your sign-in is kept."
        if state == "unavailable" { result.failed(owner: owner, message: issue) }
        else {
            let time = payload["catalog"]?["updated_at"]?.stringValue.flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
            result.receive(AccountModelCatalog(owner: owner, models: models, updatedAt: time), staleReason: state == "stale" ? issue : nil)
        }
        return result
    }
}
