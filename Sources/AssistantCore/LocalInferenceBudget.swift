import Foundation

/// A conservative planning estimate, never a promise of an iOS memory grant.
/// Qwen 3.5 4B has eight full-attention layers, four KV heads and 256-wide
/// heads: 32 KiB/token at native 16-bit cache precision. Quantized estimates
/// include packing/scale overhead. Weight quantization is never changed here.
public struct LocalInferenceBudget: Equatable, Sendable {
    public let workingBytes: Int64
    public let fixedBytes: Int64
    public let maximumContextTokens: Int
    public let selectedContextTokens: Int
    public let inputTokens: Int
    public let responseTokens: Int
    /// nil preserves the model's native cache; otherwise passed to MLX verbatim.
    public let attentionCacheBits: Int?
    public let automaticContextTokens: Int
    public let fits: Bool
    public var presets: [Int] { [8_192,16_384,32_768,65_536,131_072,262_144].filter { $0 <= maximumContextTokens } }
    public init(weightBytes: Int64, availableBytes: Int64, residentBytes: Int64 = 0,
                requestedMemoryGiB: Int = 8, requestedContextTokens: Int? = nil,
                responseTokens: Int = 2_048, supportsEfficientKV: Bool = true,
                optimizedTextRuntime: Bool = false) {
        let gib: Int64 = 1_073_741_824
        let cap = Int64(min(8, max(4, requestedMemoryGiB))) * gib
        let resident = min(cap, max(0, residentBytes))
        let weights = min(cap, max(0, weightBytes))
        // Saturate at the configured cap before adding externally measured values.
        let available = min(cap + 512 * 1_024 * 1_024, max(0, availableBytes)) + min(cap, max(0, residentBytes))
        let mib: Int64 = 1_024 * 1_024
        // Available means ADDITIONAL per-process headroom. A resident model's
        // measured process footprint is already charged by iOS, so add it back
        // once when describing the total budget and charge it once below.
        workingBytes = min(cap, max(0, available - (optimizedTextRuntime ? 192 : 512) * mib))
        if optimizedTextRuntime {
            // Cold: tokenizer/loading allowance plus a bounded text prefill and
            // recurrent state. Warm: loading allocations are in residentBytes.
            fixedBytes = resident > 0 ? resident + 128 * mib : weights + 256 * mib
        } else {
            fixedBytes = max(weights, resident) + 896 * mib
        }
        let cacheBudget = max(0, workingBytes - fixedBytes)
        automaticContextTokens = supportsEfficientKV ? 65_536 : 32_768
        let target = min(262_144, max(4_096, requestedContextTokens ?? automaticContextTokens))
        let perToken: Int64
        if supportsEfficientKV {
            if cacheBudget / 32_768 >= target { attentionCacheBits = nil; perToken = 32_768 }
            else if cacheBudget / 18_432 >= target { attentionCacheBits = 8; perToken = 18_432 }
            else { attentionCacheBits = 4; perToken = 10_240 }
        } else { attentionCacheBits = nil; perToken = 65_536 }
        // Presets describe what could fit after replanning cache precision for
        // that requested window, rather than locking the user to today's cache.
        let maximum = Int(min(262_144, cacheBudget / (supportsEfficientKV ? 10_240 : 65_536)))
        let maximumTokens = (maximum / 1_024) * 1_024
        maximumContextTokens = maximumTokens
        self.responseTokens = min(8_192, max(256, responseTokens))
        // Never silently shrink a requested window. A lower preset is an
        // explicit user choice; an unfit target fails before weights are loaded.
        selectedContextTokens = target
        inputTokens = max(0, selectedContextTokens - self.responseTokens - 1_024)
        fits = inputTokens >= 2_048 && cacheBudget / perToken >= target
    }
}
