import Foundation

/// What the platform lets us observe about access. HealthKit intentionally
/// hides whether *read* access was denied, so "requested" plus no samples is
/// ambiguous: denied, no device, or nothing recorded all look the same.
public enum HealthAccessState: String, Codable, Sendable {
    case unavailable      // health data not supported on this device
    case notDetermined    // we have not shown the permission sheet yet
    case requested        // sheet shown; actual read grants are not observable
}

/// Stage values we care about, decoupled from HKCategoryValueSleepAnalysis.
public enum SleepStage: Sendable, Equatable {
    case inBed, awake, asleepUnspecified, asleepCore, asleepDeep, asleepREM

    var countsAsSleep: Bool {
        switch self {
        case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM: true
        case .inBed, .awake: false
        }
    }
}

public struct SleepInterval: Sendable, Equatable {
    public let start: Date
    public let end: Date
    public let stage: SleepStage

    public init(start: Date, end: Date, stage: SleepStage) {
        self.start = start
        self.end = end
        self.stage = stage
    }
}

/// What a data source (HealthKit, Health Connect, a fixture) hands to the core.
/// Day keys are start-of-day in the caller's calendar. A missing key means
/// "no samples", which is different from a recorded zero.
public struct RawHealthData: Sendable {
    /// Normalized daily values keyed by metric. Quantity-based metrics such as
    /// steps and resting heart rate share this path; interval metrics can keep
    /// their native samples until their own aggregator converts them.
    public var dailyValues: [HealthMetric: [Date: Double]]
    public var sleepIntervals: [SleepInterval]
    public var latestSampleDate: [HealthMetric: Date]

    public init(
        dailyValues: [HealthMetric: [Date: Double]] = [:],
        sleepIntervals: [SleepInterval] = [],
        latestSampleDate: [HealthMetric: Date] = [:]
    ) {
        self.dailyValues = dailyValues
        self.sleepIntervals = sleepIntervals
        self.latestSampleDate = latestSampleDate
    }

    /// Compatibility initializer for existing fixtures and data sources.
    public init(
        dailySteps: [Date: Double],
        sleepIntervals: [SleepInterval] = [],
        dailyRestingHeartRate: [Date: Double] = [:],
        latestSampleDate: [HealthMetric: Date] = [:]
    ) {
        self.init(
            dailyValues: [.steps: dailySteps, .restingHeartRate: dailyRestingHeartRate],
            sleepIntervals: sleepIntervals,
            latestSampleDate: latestSampleDate
        )
    }

    public func dailyValues(for metric: HealthMetric) -> [Date: Double] {
        dailyValues[metric] ?? [:]
    }

    public static let empty = RawHealthData(dailyValues: [:])
}

/// Abstraction over the platform health store.
public protocol HealthDataSource: Sendable {
    func accessState() async -> HealthAccessState
    func requestAccess() async throws
    /// Fetch everything needed for `window`. Sleep should include the evening
    /// before the first day so the first night is complete.
    func fetch(window: DateInterval, calendar: Calendar) async throws -> RawHealthData
}
