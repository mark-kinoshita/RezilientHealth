import Foundation
import HealthKit
import InsightCore

/// HealthKit adapter. Does the platform-specific querying and hands
/// platform-neutral `RawHealthData` to InsightCore.
nonisolated final class HealthKitDataSource: HealthDataSource, @unchecked Sendable {
    let store = HKHealthStore()

    static let stepType = HKQuantityType(.stepCount)
    static let restingHRType = HKQuantityType(.restingHeartRate)
    static let sleepType = HKCategoryType(.sleepAnalysis)
    static let readTypes: Set<HKObjectType> = [stepType, restingHRType, sleepType]

    /// Write access exists only so debug builds can seed synthetic data.
    static var shareTypes: Set<HKSampleType> {
        #if DEBUG
        [stepType, restingHRType, sleepType]
        #else
        []
        #endif
    }

    func accessState() async -> HealthAccessState {
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
        let status = try? await store.statusForAuthorizationRequest(toShare: Self.shareTypes, read: Self.readTypes)
        // `.unnecessary` only means the sheet was shown; HealthKit never tells
        // us whether read access was granted.
        return status == .unnecessary ? .requested : .notDetermined
    }

    func requestAccess() async throws {
        try await store.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)
    }

    func fetch(window: DateInterval, calendar: Calendar) async throws -> RawHealthData {
        async let steps = dailyStatistics(Self.stepType, options: .cumulativeSum, unit: .count(), window: window, calendar: calendar)
        async let restingHR = dailyStatistics(Self.restingHRType, options: .discreteAverage, unit: .count().unitDivided(by: .minute()), window: window, calendar: calendar)
        async let sleep = sleepIntervals(window: window)
        async let latestSteps = latestSampleDate(Self.stepType)
        async let latestHR = latestSampleDate(Self.restingHRType)
        async let latestSleep = latestSampleDate(Self.sleepType)

        return try await RawHealthData(
            dailyValues: [.steps: steps, .restingHeartRate: restingHR],
            sleepIntervals: sleep,
            latestSampleDate: [.steps: latestSteps, .restingHeartRate: latestHR, .sleep: latestSleep].compactMapValues { $0 }
        )
    }

    /// Daily buckets via HKStatisticsCollectionQuery, which de-duplicates
    /// overlapping sources (e.g. iPhone + Watch steps). Days without samples
    /// are omitted, never reported as zero.
    private func dailyStatistics(
        _ type: HKQuantityType, options: HKStatisticsOptions, unit: HKUnit,
        window: DateInterval, calendar: Calendar
    ) async throws -> [Date: Double] {
        let predicate = HKQuery.predicateForSamples(withStart: window.start, end: window.end)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: options,
            anchorDate: calendar.startOfDay(for: window.start),
            intervalComponents: DateComponents(day: 1)
        )
        let collection = try await descriptor.result(for: store)
        var result: [Date: Double] = [:]
        collection.enumerateStatistics(from: window.start, to: window.end) { statistics, _ in
            let quantity = options.contains(.cumulativeSum) ? statistics.sumQuantity() : statistics.averageQuantity()
            if let quantity {
                result[calendar.startOfDay(for: statistics.startDate)] = quantity.doubleValue(for: unit)
            }
        }

        // Statistics queries stopped returning data older than ~30 days in
        // testing, while sample queries did not. Fill only the older, uncovered
        // part of the window from raw samples.
        let fallbackEnd = result.keys.min() ?? window.end
        guard fallbackEnd > window.start else { return result }
        let samples = try await HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: HKQuery.predicateForSamples(withStart: window.start, end: fallbackEnd))],
            sortDescriptors: []
        ).result(for: store).map {
            QuantitySampleRecord(start: $0.startDate, value: $0.quantity.doubleValue(for: unit), sourceID: $0.sourceRevision.source.bundleIdentifier)
        }
        let fallback = options.contains(.cumulativeSum)
            ? DailyQuantityAggregator.cumulativeByDay(samples, calendar: calendar)
            : DailyQuantityAggregator.averageByDay(samples, calendar: calendar)
        return DailyQuantityAggregator.merge(statistics: result, fallback: fallback)
    }

    private func sleepIntervals(window: DateInterval) async throws -> [SleepInterval] {
        // Start at 18:00 the evening before so the first night is complete.
        let start = window.start.addingTimeInterval(-6 * 3600)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: window.end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: Self.sleepType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await descriptor.result(for: store).compactMap { sample in
            guard let stage = SleepStage(healthKitValue: sample.value) else { return nil }
            return SleepInterval(start: sample.startDate, end: sample.endDate, stage: stage)
        }
    }

    /// Most recent sample regardless of window, used to detect stale data.
    private func latestSampleDate(_ type: HKSampleType) async throws -> Date? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.sample(type: type)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        return try await descriptor.result(for: store).first?.endDate
    }
}

nonisolated extension SleepStage {
    init?(healthKitValue: Int) {
        switch HKCategoryValueSleepAnalysis(rawValue: healthKitValue) {
        case .inBed: self = .inBed
        case .awake: self = .awake
        case .asleepUnspecified: self = .asleepUnspecified
        case .asleepCore: self = .asleepCore
        case .asleepDeep: self = .asleepDeep
        case .asleepREM: self = .asleepREM
        default: return nil
        }
    }
}
