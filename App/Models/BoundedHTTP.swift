import AssistantCore
import Foundation

extension URLSession {
    /// Check the advertised length and every received chunk before growing the
    /// response buffer. Retains the caller's TLS pin and redirect policy.
    nonisolated func boundedData(for request: URLRequest, maximumBytes: Int) async throws -> (Data, URLResponse) {
        let (stream, response) = try await bytes(for: request)
        defer { stream.task.cancel() }
        guard response.expectedContentLength < 0 || response.expectedContentLength <= Int64(maximumBytes) else { throw AssistantError.provider("The response exceeds this operation's size limit.") }
        var result = Data(); result.reserveCapacity(min(maximumBytes, 64 * 1024))
        for try await byte in stream {
            guard result.count < maximumBytes else { throw AssistantError.provider("The response exceeds this operation's size limit.") }
            result.append(byte)
        }
        return (result, response)
    }
}
