import AssistantCore
import HealthKit

/// Queryable types and authorizable types are different sets in HealthKit.
/// Correlations inherit access to their constituent measurements.
@MainActor
struct HealthAuthorizationPlan {
    let ordinary: Set<HKObjectType>
    let perObject: [HKObjectType]

    init(selected: Set<String>) {
        var ids = selected
        if ids.remove("HKCorrelationTypeIdentifierBloodPressure") != nil {
            ids.formUnion(["HKQuantityTypeIdentifierBloodPressureSystolic", "HKQuantityTypeIdentifierBloodPressureDiastolic"])
        }
        if ids.remove("HKCorrelationTypeIdentifierFood") != nil {
            ids.formUnion(HealthDataCatalog.entries.filter { $0.kind == "quantity" && $0.id.hasPrefix("HKQuantityTypeIdentifierDietary") }.map(\.id))
        }
        let types = Set(HealthDataCatalog.entries.filter { ids.contains($0.id) && $0.kind != "correlation" }.compactMap(HealthDataReader.objectType))
        ordinary = Set(types.filter { !$0.requiresPerObjectAuthorization() })
        perObject = types.filter { $0.requiresPerObjectAuthorization() }.sorted { $0.identifier < $1.identifier }
    }
}
