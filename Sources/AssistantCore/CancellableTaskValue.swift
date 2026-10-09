import Foundation

/// A caller can stop waiting without cancelling a shared producer that must finish an atomic credential rotation.
public enum CancellableTaskValue {
    public static func value<Value: Sendable>(of task: Task<Value, any Error>) async throws -> Value {
        let waiter = SharedTaskWaiter<Value>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiter.install(continuation)
                Task { waiter.resolve(await task.result) }
            }
        } onCancel: { waiter.resolve(.failure(CancellationError())) }
    }
}
private final class SharedTaskWaiter<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Value, any Error>?
    private var continuation: CheckedContinuation<Value, any Error>?
    func install(_ continuation: CheckedContinuation<Value, any Error>) {
        let ready = lock.withLock { () -> Result<Value, any Error>? in
            if let result { return result }
            self.continuation = continuation
            return nil
        }
        if let ready { continuation.resume(with: ready) }
    }
    func resolve(_ value: Result<Value, any Error>) {
        let waiting = lock.withLock { () -> CheckedContinuation<Value, any Error>? in
            guard result == nil else { return nil }
            result = value
            let waiting = continuation; continuation = nil
            return waiting
        }
        waiting?.resume(with: value)
    }
}
