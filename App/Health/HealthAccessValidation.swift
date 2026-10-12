import Foundation
import HealthKit
import AssistantCore

struct HealthAccessOutcome {
    var selected: Set<String>
    var unavailable: [String: String]
}

/// Validates the request without opening a permission sheet or reading records.
/// A single unsupported OS type must not invalidate every selected category.
@MainActor
enum HealthAccessValidation {
    static func partition(_ types: Set<HKObjectType>,
                          check: @MainActor (Set<HKObjectType>) async throws -> Void) async throws -> (Set<HKObjectType>, [String: String]) {
        guard !types.isEmpty else { return ([], [:]) }
        do { try await check(types); return (types, [:]) }
        catch {
            let failure = error as NSError
            guard failure.domain == "Assistant.FrameworkValidation" || (failure.domain == HKErrorDomain && failure.code == HKError.Code.errorInvalidArgument.rawValue) else { throw error }
            if types.count == 1 {
                return ([], [types.first!.identifier: String((failure.localizedFailureReason ?? failure.localizedDescription).prefix(500))])
            }
            let ordered = types.sorted { $0.identifier < $1.identifier }, middle = ordered.count / 2
            let left = try await partition(Set(ordered[..<middle]), check: check)
            let right = try await partition(Set(ordered[middle...]), check: check)
            return (left.0.union(right.0), left.1.merging(right.1, uniquingKeysWith: { first, _ in first }))
        }
    }
}
