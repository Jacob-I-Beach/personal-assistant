import Foundation

public struct CapabilityAvailability: Equatable, Sendable {
    public enum State: String, Sendable { case ready, checking, unavailable, needsSetup, blocked }
    public let capability: String
    public let route: String
    public let state: State
    public let detail: String
    public let observedAt: Date?
    public let recovery: AppPresentation?
    public init(capability: String, route: String, state: State, detail: String, observedAt: Date? = nil, recovery: AppPresentation? = nil) {
        self.capability = capability; self.route = route; self.state = state; self.detail = detail; self.observedAt = observedAt; self.recovery = recovery
    }
}
public enum RecoveryCategory: String, Sendable { case connection, capacity, permission, missingSource, importFailure, unknownWriteOutcome }
public struct LocalRecovery: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let conversationID: UUID?
    public let category: RecoveryCategory
    public let title: String
    public let detail: String
    public let retained: String
    public var canRetry: Bool { category != .unknownWriteOutcome }
    public init(id: UUID = UUID(), conversationID: UUID?, category: RecoveryCategory, title: String, detail: String, retained: String) {
        self.id = id; self.conversationID = conversationID; self.category = category; self.title = title; self.detail = detail; self.retained = retained
    }
}
public struct AttachmentDraft: Identifiable, Equatable, Sendable {
    public enum State: String, Sendable { case preparing, ready, partial, unreadable }
    public let id: UUID
    public let conversationID: UUID
    public let source: String
    public var state: State
    public var fileID: UUID?
    public var detail: String
    public var containsHealthData = false
    public init(id: UUID = UUID(), conversationID: UUID, source: String, state: State = .preparing, fileID: UUID? = nil, detail: String = "") { self.id = id; self.conversationID = conversationID; self.source = source; self.state = state; self.fileID = fileID; self.detail = detail }
}
public enum SurfaceInput {
    public static func accepts(_ number: Double, specification: JSONValue) -> Bool {
        guard number.isFinite, let low = specification["min"]?.numberValue, let high = specification["max"]?.numberValue, let step = specification["step"]?.numberValue, step > 0, (low...high).contains(number) else { return false }
        let units = (number - low) / step
        return abs(units - units.rounded()) <= max(1e-8, abs(units) * 1e-10)
    }
}
