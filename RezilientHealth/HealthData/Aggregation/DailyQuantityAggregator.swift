import Foundation

/// One raw quantity sample, decoupled from HKQuantitySample.
public struct QuantitySampleRecord: Sendable, Equatable {
    public let start: Date
    public let value: Double
    /// Identifies the recording device/app, used to avoid double counting.
    public let sourceID: String

    public init(start: Date, value: Double, sourceID: String) {
        self.start = start
        self.value = value
        self.sourceID = sourceID
    }
}

/// Daily totals computed from raw samples. Used for days the platform's
/// statistics API doesn't return (on iOS 27 we observed statistics queries
/// returning nothing older than ~30 days while sample queries still did).
///
/// Decisions (tested in DailyQuantityAggregatorTests):
/// - Cumulative metrics (steps): sum per source per day, then take the
///   largest source total. An iPhone and a Watch both counting the same walk
///   must not be added together. This can undercount when sources cover
///   different parts of the day; HealthKit's own statistics merge by source
///   priority, which is why they're preferred where available.
/// - Discrete metrics (resting HR): mean of the day's samples.
public enum DailyQuantityAggregator {
    public static func cumulativeByDay(_ samples: [QuantitySampleRecord], calendar: Calendar) -> [Date: Double] {
        var perSource: [Date: [String: Double]] = [:]
        for sample in samples {
            perSource[calendar.startOfDay(for: sample.start), default: [:]][sample.sourceID, default: 0] += sample.value
        }
        return perSource.compactMapValues { $0.values.max() }
    }

    public static func averageByDay(_ samples: [QuantitySampleRecord], calendar: Calendar) -> [Date: Double] {
        Dictionary(grouping: samples) { calendar.startOfDay(for: $0.start) }
            .mapValues { day in day.map(\.value).reduce(0, +) / Double(day.count) }
    }

    /// Statistics win where present; samples fill only days statistics didn't cover.
    public static func merge(statistics: [Date: Double], fallback: [Date: Double]) -> [Date: Double] {
        statistics.merging(fallback) { stat, _ in stat }
    }
}
