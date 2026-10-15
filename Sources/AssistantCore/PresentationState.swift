import Foundation

public enum AppPresentation: Hashable, Identifiable, Sendable {
    case models, library, connections, settings, health, watch, task, inbox, planning, folders, projects, memory, recovery, activityPreview
    case review(UUID), savedConversation(UUID, message: UUID?), revisions(UUID)
    public var id: String { String(describing: self) }
    public var isReview: Bool { if case .review = self { true } else { false } }
}
/// One owner for root presentations. A transition waits for the actual system
/// dismissal, and a native review cannot be replaced by navigation elsewhere.
public struct PresentationState: Equatable, Sendable {
    public private(set) var active: AppPresentation?
    public private(set) var pending: AppPresentation?
    public private(set) var dismissing: AppPresentation?
    public init() {}
    public mutating func request(_ route: AppPresentation) {
        guard route != active else { return }
        if active == nil && dismissing == nil { active = route; return }
        if pending?.isReview != true { pending = route }
        if active?.isReview != true { beginDismissal() }
    }
    public mutating func beginDismissal() { if let active { dismissing = active; self.active = nil } }
    @discardableResult public mutating func didDismiss() -> AppPresentation? {
        let old = dismissing ?? active
        dismissing = nil; active = pending; pending = nil
        return old
    }
    public mutating func cancel(_ route: AppPresentation) {
        if pending == route { pending = nil }
        if active == route { beginDismissal() }
    }
}
public struct ExecutionOwner: Equatable, Sendable {
    public let conversationID: UUID
    public let turnID: UUID
    public init(conversationID: UUID, turnID: UUID) { self.conversationID = conversationID; self.turnID = turnID }
    public func matches(conversationID: UUID, turnID: UUID?) -> Bool { self.conversationID == conversationID && self.turnID == turnID }
}
