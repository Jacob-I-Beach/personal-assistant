import AssistantCore
import Foundation
import HealthKit

@MainActor
final class HealthOverviewService {
    private let store = HKHealthStore()
    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    func requestAccess() async throws {
        guard isAvailable else { throw AssistantError.provider("Health data is unavailable on this device.") }
        let read: Set<HKObjectType> = [HKQuantityType(.stepCount), HKCategoryType(.sleepAnalysis), HKObjectType.workoutType()]
        try await store.requestAuthorization(toShare: [], read: read)
        // A completed authorization sheet does not reveal which read permissions were granted.
    }
    func overview(now: Date = Date()) async throws -> HealthOverview {
        guard isAvailable else { throw AssistantError.provider("Health data is unavailable on this device.") }
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now)
        let stepsDescriptor = HKStatisticsCollectionQueryDescriptor(predicate: .quantitySample(type: HKQuantityType(.stepCount), predicate: predicate),
            options: .cumulativeSum, anchorDate: start, intervalComponents: DateComponents(day: 1))
        let statistics = try await stepsDescriptor.result(for: store)
        var steps: [Date: Double] = [:]
        statistics.enumerateStatistics(from: start, to: now) { statistic, _ in
            if let quantity = statistic.sumQuantity() { steps[calendar.startOfDay(for: statistic.startDate)] = quantity.doubleValue(for: .count()) }
        }
        try Task.checkCancellation()
        let sleepDescriptor = HKSampleQueryDescriptor(predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\HKCategorySample.startDate, order: .forward)], limit: 10_000)
        let samples = try await sleepDescriptor.result(for: store)
        let asleep = Set([HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                          HKCategoryValueSleepAnalysis.asleepDeep.rawValue, HKCategoryValueSleepAnalysis.asleepREM.rawValue])
        let sleep = samples.filter { asleep.contains($0.value) }.map {
            SleepInterval(start: $0.startDate, end: $0.endDate, source: $0.sourceRevision.source.name)
        }
        try Task.checkCancellation()
        let workoutDescriptor = HKSampleQueryDescriptor(predicates: [.workout(predicate)], sortDescriptors: [SortDescriptor(\HKWorkout.startDate, order: .reverse)], limit: 200)
        let workouts = try await workoutDescriptor.result(for: store)
        let records = workouts.map { workout in
            WorkoutRecord(id: workout.uuid, start: workout.startDate, minutes: workout.duration / 60,
                          activity: Self.name(workout.workoutActivityType), source: workout.sourceRevision.source.name)
        }
        var report = HealthOverview(rangeStart: start, rangeEnd: now, calendar: calendar, steps: steps, sleep: sleep, workouts: records)
        if samples.count == 10_000 { report.coverageNote += " The sleep query reached its record limit; coverage may be partial." }
        if workouts.count == 200 { report.coverageNote += " Only the latest 200 workouts in the selected range are included." }
        return report
    }
    private static func name(_ activity: HKWorkoutActivityType) -> String {
        switch activity {
        case .walking: "Walking"
        case .running: "Running"
        case .cycling: "Cycling"
        case .swimming: "Swimming"
        case .hiking: "Hiking"
        case .traditionalStrengthTraining: "Strength training"
        case .functionalStrengthTraining: "Functional strength"
        case .highIntensityIntervalTraining: "Interval training"
        case .yoga: "Yoga"
        case .pilates: "Pilates"
        case .rowing: "Rowing"
        case .elliptical: "Elliptical"
        default: "Other workout"
        }
    }
}
