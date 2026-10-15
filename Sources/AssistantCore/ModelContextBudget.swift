import Foundation

/// Catalog defaults and maximum capacity are distinct. This is a working input
/// budget, not a tokenizer or a promise that every service/account accepts 1M.
public struct ModelContextBudget: Equatable, Sendable {
    public let modelWindow: Int
    public let maximumInputTokens: Int
    public let selectedInputTokens: Int
    public let outputReserve: Int
    public let compactionInputTokens: Int
    public let compactionOutputReserve: Int
    public let limitSource: String
    public init(model: String, advertisedWindow: Int? = nil, advertisedMaximumWindow: Int? = nil, requestedInputTokens: Int? = nil) {
        let documented: Int? = ["gpt-6-astra", "gpt-6.1-sol", "gpt-6-sol", "gpt-6-luna"].contains(model.lowercased()) ? 1_050_000 : nil
        let advertised = advertisedWindow.flatMap { (8_192...10_000_000).contains($0) ? $0 : nil }
        let maximum = advertisedMaximumWindow.flatMap { (8_192...10_000_000).contains($0) ? $0 : nil }
        modelWindow = maximum ?? documented ?? advertised ?? 32_768
        limitSource = maximum != nil ? "Maximum offered by this connection" : documented != nil ? "Published model capacity; the connection enforces its limits" : advertised != nil ? "Your model catalog" : "Conservative default"
        let minimumReplySpace = min(16_384, modelWindow / 4)
        maximumInputTokens = min(1_000_000, modelWindow - minimumReplySpace)
        selectedInputTokens = min(maximumInputTokens, max(4_096, requestedInputTokens ?? min(128_000, maximumInputTokens)))
        let outputMaximum = documented != nil ? 128_000 : min(32_768, modelWindow / 4)
        let activeInput = selectedInputTokens - ContextReserve.amount(in: selectedInputTokens)
        // The reserve is unoccupied headroom. A normal request carries only
        // active input; subtracting the full allowance falsely reports 16K at
        // the connection's largest preset. Compaction is a separate request.
        outputReserve = min(outputMaximum, modelWindow - activeInput)
        compactionInputTokens = min(selectedInputTokens, documented != nil ? 922_000 : selectedInputTokens)
        compactionOutputReserve = min(outputMaximum, modelWindow - compactionInputTokens)
    }
    public var textByteBudget: Int { selectedInputTokens * 3 }
    public var compactionReserveTokens: Int { ContextReserve.amount(in: selectedInputTokens) }
    public var activeInputTokens: Int { selectedInputTokens - compactionReserveTokens }
    public var presets: [Int] { Array(Set([16_000, 32_000, 64_000, 128_000, 256_000, 512_000, 1_000_000, maximumInputTokens].filter { $0 <= maximumInputTokens })).sorted() }
}
