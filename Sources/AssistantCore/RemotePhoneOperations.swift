import Foundation

/// Native operations remain serial (there is one review surface), while the
/// independent task subscription continues to project server progress.
public actor RemotePhoneOperations {
    public typealias Handler = @Sendable (ToolCall) async throws -> Void
    private var queue: [ToolCall] = []
    private var seen = Set<String>()
    private var worker: Task<Void, Never>?
    private var failure: (any Error)?
    private var currentID: String?
    private var stopped = false
    private let handler: Handler
    public init(handler: @escaping Handler) { self.handler = handler }
    public func enqueue(_ calls: [ToolCall]) {
        guard !stopped else { return }
        for call in calls where seen.insert(call.id).inserted { queue.append(call) }
        guard worker == nil, !queue.isEmpty, failure == nil else { return }
        worker = Task { await drain() }
    }
    private func drain() async {
        defer { currentID = nil; worker = nil }
        while !queue.isEmpty, !Task.isCancelled {
            let call = queue.removeFirst()
            currentID = call.id
            do { try await handler(call) }
            catch { if !Task.isCancelled { failure = error }; break }
        }
    }
    /// An authoritative receipt may arrive from the PC review surface while
    /// the phone still displays the same review. Close only that waiter and
    /// allow subsequent native requests to proceed.
    public func complete(_ id: String) async {
        queue.removeAll { $0.id == id }
        if currentID == id { let task = worker; task?.cancel(); await task?.value }
        if Task.isCancelled { await stop(); return }
        guard !stopped, worker == nil, !queue.isEmpty, failure == nil else { return }
        worker = Task { await drain() }
    }
    public func check() throws { if let failure { throw failure } }
    public var isIdle: Bool { worker == nil && queue.isEmpty }
    public func stop() async {
        stopped = true; queue = []
        let task = worker; task?.cancel(); await task?.value
    }
}
