import Foundation

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
    /// Start of the first day through `generatedAt`: two periods plus today.
    public let window: DateInterval
    public let range: TimeRange
    public let access: HealthAccessState
    public let series: [HealthMetric: MetricSeries]

    public func series(_ metric: HealthMetric) -> MetricSeries {
        series[metric] ?? MetricSeries(metric: metric, days: [], lastSampleDate: nil)
    }
}
