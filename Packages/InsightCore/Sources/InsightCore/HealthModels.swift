import Foundation

/// The metrics this prototype reads. Anything else is explicitly "not tracked"
/// so the model can say so instead of guessing.
public enum HealthMetric: String, CaseIterable, Codable, Sendable, Identifiable {
    case steps
    case sleep
    case restingHeartRate = "resting_heart_rate"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .steps: "Steps"
        case .sleep: "Sleep"
        case .restingHeartRate: "Resting heart rate"
        }
    }

    public var unit: String {
        switch self {
        case .steps: "steps"
        case .sleep: "hours asleep"
        case .restingHeartRate: "bpm"
        }
    }

    /// Whether today's value is final. Steps and resting HR accumulate through
    /// the day; "today's" sleep is last night, which has already ended.
    public var todayIsComplete: Bool { self == .sleep }
}

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
    public var dailySteps: [Date: Double]
    public var sleepIntervals: [SleepInterval]
    public var dailyRestingHeartRate: [Date: Double]
    public var latestSampleDate: [HealthMetric: Date]

    public init(
        dailySteps: [Date: Double] = [:],
        sleepIntervals: [SleepInterval] = [],
        dailyRestingHeartRate: [Date: Double] = [:],
        latestSampleDate: [HealthMetric: Date] = [:]
    ) {
        self.dailySteps = dailySteps
        self.sleepIntervals = sleepIntervals
        self.dailyRestingHeartRate = dailyRestingHeartRate
        self.latestSampleDate = latestSampleDate
    }

    public static let empty = RawHealthData()
}

/// Abstraction over the platform health store.
public protocol HealthDataSource: Sendable {
    func accessState() async -> HealthAccessState
    func requestAccess() async throws
    /// Fetch everything needed for `window`. Sleep should include the evening
    /// before the first day so the first night is complete.
    func fetch(window: DateInterval, calendar: Calendar) async throws -> RawHealthData
}

public struct DailyValue: Sendable, Equatable, Identifiable {
    public let day: Date
    /// `nil` means no samples were recorded. Never coerce to zero.
    public let value: Double?
    /// True for today's in-progress value of an accumulating metric.
    public let isPartial: Bool

    public var id: Date { day }

    public init(day: Date, value: Double?, isPartial: Bool) {
        self.day = day
        self.value = value
        self.isPartial = isPartial
    }
}

public struct MetricSeries: Sendable, Equatable {
    public let metric: HealthMetric
    /// One entry per day in the window, oldest first, including today.
    public let days: [DailyValue]
    public let lastSampleDate: Date?

    public var hasAnyData: Bool { days.contains { $0.value != nil } }
}

public struct HealthSnapshot: Sendable, Equatable {
    public let generatedAt: Date
    public let calendar: Calendar
    /// Start of the first day through `generatedAt`.
    public let window: DateInterval
    public let access: HealthAccessState
    public let series: [HealthMetric: MetricSeries]

    public func series(_ metric: HealthMetric) -> MetricSeries {
        series[metric] ?? MetricSeries(metric: metric, days: [], lastSampleDate: nil)
    }
}
