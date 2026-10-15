import Foundation
import InsightCore

/// Everything a metric card renders, already worded and formatted.
public struct MetricCardState: Sendable, Equatable, Identifiable {
    public struct ChartPoint: Sendable, Equatable, Identifiable {
        public let day: Date
        /// `nil` renders as an explicit "no data" column, never a zero bar.
        public let value: Double?
        public let isPartial: Bool
        public let accessibilityLabel: String
        public let accessibilityValue: String

        public var id: Date { day }
    }

    public let metric: HealthMetric
    public let title: String
    public let headline: String
    /// Headline is de-emphasized when there's no usable average.
    public let isHeadlineMuted: Bool
    public let detail: String
    /// Hidden when there's no data at all (a "0 of 7 days" line adds nothing).
    public let coverageNote: String?
    public let isStale: Bool
    /// Empty when there is nothing to chart.
    public let chart: [ChartPoint]
    /// Sleep cards draw a dashed target line at this value.
    public let targetLine: Double?
    /// Resting heart rate reads better without a zero baseline.
    public let chartIncludesZero: Bool

    public var id: HealthMetric { metric }
}

/// Turns InsightCore facts into member-facing copy. Pure and deterministic.
enum MetricCardPresenter {
    static func card(
        for insight: MetricInsight,
        series: MetricSeries,
        access: HealthAccessState,
        calendar: Calendar
    ) -> MetricCardState {
        let format = DisplayFormatter(calendar: calendar)
        let metric = insight.metric
        let name = metric.displayName.lowercased()
        let recent = insight.recent

        let headline: String
        var detail: String
        switch insight.status {
        case .noData:
            headline = "No \(name) data in the last \(series.days.count) days"
            detail = noDataExplanation(name: name, access: access, lastSample: insight.lastSampleDate, format: format)
        case .insufficientData:
            headline = "Not enough recent \(name) data"
            detail = "Recorded on \(recent.daysWithData) of the last \(recent.daysInPeriod) days. "
                + "We show an average once at least \(InsightEngine.minimumDaysWithData) days have data."
        case .ok:
            (headline, detail) = describe(insight, format: format)
        }
        if insight.isStale, let last = insight.lastSampleDate {
            detail += " Last recorded \(format.day(last)), so this may not reflect recent days."
        }

        return MetricCardState(
            metric: metric,
            title: metric.displayName,
            headline: headline,
            isHeadlineMuted: insight.status != .ok,
            detail: detail,
            coverageNote: insight.status == .noData ? nil
                : "Based on \(recent.daysWithData) of \(recent.daysInPeriod) days (\(format.range(recent))). "
                    + "Days with no data are left out, not counted as zero.",
            isStale: insight.isStale,
            chart: series.hasAnyData ? series.days.map { point($0, metric: metric, format: format) } : [],
            targetLine: metric == .sleep ? InsightEngine.sleepTargetHours : nil,
            chartIncludesZero: metric != .restingHeartRate
        )
    }

    private static func describe(_ insight: MetricInsight, format: DisplayFormatter) -> (String, String) {
        guard let average = insight.recent.average else { return ("", "") }
        let comparison: String
        switch (insight.metric, insight.change, insight.prior.average) {
        case (.steps, let change?, let prior?):
            let pct = prior > 0 ? change / prior * 100 : 0
            comparison = abs(pct) < 5
                ? "About the same as the week before (\(format.int(prior)))."
                : "\(pct > 0 ? "Up" : "Down") \(format.int(abs(pct)))% from \(format.int(prior)) the week before."
        case (.sleep, let change?, let prior?):
            comparison = abs(change) < 0.25
                ? "About the same as the week before (\(format.hours(prior)))."
                : "\(format.hours(abs(change))) \(change > 0 ? "more" : "less") than the week before (\(format.hours(prior)))."
        case (.restingHeartRate, let change?, let prior?):
            comparison = abs(change) < 2
                ? "About the same as the week before (\(format.int(prior)) bpm)."
                : "\(format.int(abs(change))) bpm \(change > 0 ? "higher" : "lower") than the week before (\(format.int(prior)) bpm)."
        default:
            comparison = "Not enough data from the week before to compare."
        }

        switch insight.metric {
        case .steps:
            return ("Averaging \(format.int(average)) steps a day", comparison)
        case .sleep:
            let met = insight.nightsMeetingSleepTarget ?? 0
            let target = Int(InsightEngine.sleepTargetHours)
            return (
                "Averaging \(format.hours(average)) asleep",
                "\(met) of \(insight.recent.daysWithData) recorded nights reached \(target) hours. " + comparison
            )
        case .restingHeartRate:
            return ("Resting heart rate averaging \(format.int(average)) bpm", comparison)
        }
    }

    private static func noDataExplanation(
        name: String, access: HealthAccessState, lastSample: Date?, format: DisplayFormatter
    ) -> String {
        if let lastSample {
            return "The most recent \(name) sample is from \(format.day(lastSample)), before this window."
        }
        switch access {
        case .unavailable:
            return "Health data isn't available on this device."
        case .notDetermined:
            return "Connect Apple Health to see this."
        case .requested:
            // HealthKit does not reveal denied read access, so we can't tell these apart.
            return "This can mean Health access is off for this metric, or no device recorded it. "
                + "It doesn't mean nothing happened."
        }
    }

    private static func point(_ day: DailyValue, metric: HealthMetric, format: DisplayFormatter) -> MetricCardState.ChartPoint {
        let value: String = switch (day.value, day.isPartial) {
        case (nil, _): "No data recorded"
        case (let v?, true): "\(format.spoken(v, metric)) so far today"
        case (let v?, false): format.spoken(v, metric)
        }
        return .init(
            day: day.day, value: day.value, isPartial: day.isPartial,
            accessibilityLabel: format.longDay(day.day), accessibilityValue: value
        )
    }
}
