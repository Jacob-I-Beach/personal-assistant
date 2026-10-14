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
                responseTokens: Int = 2_048, supportsEfficientKV: Bool = true,
                optimizedTextRuntime: Bool = false) {
        let gib: Int64 = 1_073_741_824
        let cap = Int64(min(8, max(4, requestedMemoryGiB))) * gib
        let available = max(0, availableBytes) + max(0, residentBytes)
        let mib: Int64 = 1_024 * 1_024
        // Available means ADDITIONAL per-process headroom. A resident model's
        // measured process footprint is already charged by iOS, so add it back
        // once when describing the total budget and charge it once below.
        workingBytes = min(cap, max(0, available - (optimizedTextRuntime ? 192 : 512) * mib))
        if optimizedTextRuntime {
            // Cold: tokenizer/loading allowance plus a bounded text prefill and
            // recurrent state. Warm: loading allocations are in residentBytes.
            fixedBytes = residentBytes > 0 ? residentBytes + 128 * mib : max(0, weightBytes) + 256 * mib
        } else {
            fixedBytes = max(max(0, weightBytes), residentBytes) + 896 * mib
        }
        let perToken: Int64 = supportsEfficientKV ? 10_240 : 65_536
        let maximum = Int(min(262_144, max(0, workingBytes - fixedBytes) / perToken))
        let maximumTokens = (maximum / 1_024) * 1_024
        maximumContextTokens = maximumTokens
        self.responseTokens = min(8_192, max(256, responseTokens))
        let target = max(4_096, requestedContextTokens ?? 32_768)
        let standard = [4_096,8_192,16_384,32_768,65_536,131_072,262_144]
        selectedContextTokens = maximumTokens >= target ? target : (standard.last { $0 <= maximumTokens } ?? maximumTokens)
        inputTokens = max(0, selectedContextTokens - self.responseTokens - 1_024)
        fits = inputTokens >= 2_048
    }
}
