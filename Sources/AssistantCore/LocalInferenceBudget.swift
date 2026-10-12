import Foundation

/// A conservative planning estimate, never a promise of an iOS memory grant.
/// Qwen 3.5 4B has eight full-attention layers, four KV heads and 256-wide
/// heads. Four-bit KV plus scale/packing overhead is budgeted at 10 KiB/token.
public struct LocalInferenceBudget: Equatable, Sendable {
    public let workingBytes: Int64
    public let fixedBytes: Int64
    public let maximumContextTokens: Int
    public let selectedContextTokens: Int
    public let inputTokens: Int
    public let responseTokens: Int
    public let fits: Bool
    public var presets: [Int] { [8_192,16_384,32_768,65_536,131_072,262_144].filter { $0 <= maximumContextTokens } }
    public init(weightBytes: Int64, availableBytes: Int64, residentBytes: Int64 = 0,
                requestedMemoryGiB: Int = 8, requestedContextTokens: Int? = nil,
                responseTokens: Int = 2_048, supportsEfficientKV: Bool = true) {
        let gib: Int64 = 1_073_741_824
        let cap = Int64(min(8, max(4, requestedMemoryGiB))) * gib
        let available = max(0, availableBytes) + max(0, residentBytes)
        workingBytes = min(cap, max(0, available - 512 * 1_024 * 1_024))
        fixedBytes = max(0, weightBytes) + 896 * 1_024 * 1_024
        let perToken: Int64 = supportsEfficientKV ? 10_240 : 65_536
        let maximum = Int(min(262_144, max(0, workingBytes - fixedBytes) / perToken))
        maximumContextTokens = (maximum / 1_024) * 1_024
        self.responseTokens = min(8_192, max(256, responseTokens))
        selectedContextTokens = min(maximumContextTokens, max(4_096, requestedContextTokens ?? 32_768))
        inputTokens = max(0, selectedContextTokens - self.responseTokens - 1_024)
        fits = inputTokens >= 2_048
    }
}
