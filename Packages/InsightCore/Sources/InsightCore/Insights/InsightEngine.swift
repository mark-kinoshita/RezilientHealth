import Foundation

/// Average over one 7-day period, counting only days that have data.
public struct PeriodStats: Sendable, Equatable, Codable {
    public let average: Double?
    public let daysWithData: Int
    public let daysInPeriod: Int
    public let firstDay: Date?
    public let lastDay: Date?
    public let minimumDaysWithData: Int

    /// True when the average is backed by enough days to be shown.
    public var isSufficient: Bool { average != nil && daysWithData >= minimumDaysWithData }
}

/// The computed facts behind one metric's insight. Numbers and states only;
/// wording belongs to the presentation layer (InsightPresentation).
public struct MetricInsight: Sendable, Equatable, Identifiable {
    public enum Status: String, Sendable, Codable {
        case ok
        case insufficientData = "insufficient_data"
        case noData = "no_data"
    }

    public let metric: HealthMetric
    public let status: Status
    public let isStale: Bool
    public let lastSampleDate: Date?
    public let recent: PeriodStats
    public let prior: PeriodStats
    /// Signed change recent − prior, only when both periods are sufficient.
    public let change: Double?
    /// Sleep only: recorded nights in the recent period at or above the target.
    public let nightsMeetingSleepTarget: Int?

    public var id: HealthMetric { metric }
}

/// Deterministic, on-device insight calculation. The LLM never computes these
/// numbers; it receives them (see InsightContextBuilder).
public enum InsightEngine {
    /// Data older than this is called out as stale.
    public static let staleAfter: TimeInterval = 48 * 3600
    /// Hours of sleep counted as meeting the common adult target.
    public static let sleepTargetHours = 7.0

    public static func insights(for snapshot: HealthSnapshot) -> [MetricInsight] {
        HealthMetric.allCases.map { insight(for: snapshot.series($0), now: snapshot.generatedAt, range: snapshot.range) }
    }

    /// The days in the current period: completed days only for accumulating
    /// metrics (today's partial total would drag the average down).
    public static func currentDays(of series: MetricSeries, range: TimeRange) -> [DailyValue] {
        Array(series.days.filter { !$0.isPartial }.suffix(range.days))
    }

    public static func periods(for series: MetricSeries, range: TimeRange) -> (recent: PeriodStats, prior: PeriodStats) {
        let completed = series.days.filter { !$0.isPartial }
        let recent = Array(completed.suffix(range.days))
        let prior = Array(completed.dropLast(range.days).suffix(range.days))
        return (stats(recent, minimum: range.minimumDaysWithData), stats(prior, minimum: range.minimumDaysWithData))
    }

    static func stats(_ days: [DailyValue], minimum: Int) -> PeriodStats {
        let values = days.compactMap(\.value)
        return PeriodStats(
            average: values.isEmpty ? nil : values.reduce(0, +) / Double(values.count),
            daysWithData: values.count,
            daysInPeriod: days.count,
            firstDay: days.first?.day,
            lastDay: days.last?.day,
            minimumDaysWithData: minimum
        )
    }

    public static func isStale(_ series: MetricSeries, now: Date) -> Bool {
        guard let last = series.lastSampleDate else { return false }
        return now.timeIntervalSince(last) > staleAfter
    }

    static func insight(for series: MetricSeries, now: Date, range: TimeRange) -> MetricInsight {
        let (recent, prior) = periods(for: series, range: range)
        let status: MetricInsight.Status =
            !series.hasAnyData ? .noData : recent.isSufficient ? .ok : .insufficientData
        let change: Double? = status == .ok && prior.isSufficient
            ? recent.average.flatMap { r in prior.average.map { r - $0 } }
            : nil
        let nightsMeetingTarget: Int? = series.metric == .sleep && status == .ok
            ? currentDays(of: series, range: range).compactMap(\.value).filter { $0 >= sleepTargetHours }.count
            : nil
        return MetricInsight(
            metric: series.metric,
            status: status,
            isStale: status != .noData && isStale(series, now: now),
            lastSampleDate: series.lastSampleDate,
            recent: recent,
            prior: prior,
            change: change,
            nightsMeetingSleepTarget: nightsMeetingTarget
        )
    }
}

/// Minimal formatting used by the deterministic mock model client.
struct Formatting {
    static func hours(_ value: Double) -> String {
        let totalMinutes = Int((value * 60).rounded())
        return "\(totalMinutes / 60)h \(totalMinutes % 60)m"
    }
}
