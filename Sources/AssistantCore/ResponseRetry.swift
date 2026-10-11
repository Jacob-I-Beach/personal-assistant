import Foundation

/// Transport failures carry a safe classification, never an arbitrary server response body.
public struct ModelHTTPError: Error, LocalizedError, Sendable {
    public let status: Int
    public let retryAfter: Double?
    public let retryable: Bool
    public init(status: Int, retryAfter: Double? = nil, code: String? = nil) {
        self.status = status; self.retryAfter = retryAfter
        retryable = [408, 409, 429, 500, 502, 503, 504].contains(status)
            && !["insufficient_quota", "billing_hard_limit_reached", "usage_limit_reached"].contains(code ?? "")
    }
    public var errorDescription: String? {
        switch status {
        case 401, 403: "The model connection needs authorization. Check your account in Connections. Your work is saved."
        case 429: "The model service is limiting requests. Your work is saved; try again when access is available."
        default: "The model service could not finish this request (HTTP \(status)). Your work is saved."
        }
    }
}

public struct ResponseRetryPolicy: Sendable {
    public let maximumRetries: Int
    public let baseDelay: Double
    public init(maximumRetries: Int = 5, baseDelay: Double = 1) {
        self.maximumRetries = min(5, max(0, maximumRetries)); self.baseDelay = max(0, baseDelay)
    }
    public func delay(after error: any Error, retry: Int) -> Double? {
        guard (1...max(1, maximumRetries)).contains(retry), retry <= maximumRetries,
              !(error is CancellationError) else { return nil }
        let retryable: Bool
        if let http = error as? ModelHTTPError { retryable = http.retryable }
        else if let url = error as? URLError {
            retryable = [.timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .resourceUnavailable].contains(url.code)
        } else if let app = error as? AssistantError, case .incompleteResponse = app { retryable = true }
        else { retryable = false }
        guard retryable else { return nil }
        let proposed = (error as? ModelHTTPError)?.retryAfter ?? baseDelay * pow(2, Double(retry - 1))
        // A long service cooldown needs a later user decision, not a tight retry loop.
        guard proposed <= 60 else { return nil }
        return max(0, proposed)
    }
}
