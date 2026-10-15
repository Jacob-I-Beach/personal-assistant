import Foundation

/// Native operations remain serial (there is one review surface), while the
/// independent task subscription continues to project server progress.
public actor RemotePhoneOperations {
    public typealias Handler = @Sendable (ToolCall) async throws -> Void
    private var queue: [ToolCall] = []
    private var seen = Set<String>()
    private var worker: Task<Void, Never>?
    private var failure: (any Error)?
    private let handler: Handler
    public init(handler: @escaping Handler) { self.handler = handler }
    public func enqueue(_ calls: [ToolCall]) {
        for call in calls where seen.insert(call.id).inserted { queue.append(call) }
        guard worker == nil, !queue.isEmpty, failure == nil else { return }
        worker = Task { await drain() }
    }
    private func drain() async {
        while !queue.isEmpty, !Task.isCancelled {
            let call = queue.removeFirst()
            do { try await handler(call) }
            catch { if !Task.isCancelled { failure = error }; break }
        }
        worker = nil
    }
    public func check() throws { if let failure { throw failure } }
    public var isIdle: Bool { worker == nil && queue.isEmpty }
    public func stop() async {
        let task = worker; task?.cancel(); await task?.value; queue = []
    }
}
