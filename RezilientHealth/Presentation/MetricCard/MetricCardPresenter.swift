import Foundation

/// Turns calculated health facts into member-facing copy. Pure and deterministic.
enum MetricCardPresenter {
    static func card(
        for insight: MetricInsight,
        series: MetricSeries,
        range: TimeRange,
        access: HealthAccessState,
        calendar: Calendar
    ) -> MetricCardState {
        let format = DisplayFormatter(calendar: calendar)
        let metric = insight.metric
        let name = metric.displayName.lowercased()
        let recent = insight.recent
        let average = insight.status == .ok ? recent.average : nil

        let headline: String
        var detail: String
        let statusLine: String?
        switch insight.status {
        case .noData:
            headline = "No \(name) data in \(range.currentLabel)"
            detail = noDataExplanation(name: name, access: access, lastSample: insight.lastSampleDate, format: format)
            statusLine = insight.lastSampleDate == nil ? "No data recorded" : "No recent data"
        case .insufficientData:
            headline = "Not enough \(name) data in \(range.currentLabel)"
            detail = "Recorded on \(recent.daysWithData) of \(recent.daysInPeriod) days. "
                + "We show an average once at least \(recent.minimumDaysWithData) days have data."
            statusLine = "Not enough data"
        case .ok:
            (headline, detail) = describe(insight, range: range, format: format)
            statusLine = nil
        }
        if insight.isStale, let last = insight.lastSampleDate {
            detail += " Last recorded \(format.day(last)), so this may not reflect recent days."
        }

        let chartDays = series.days.suffix(range.days + 1)
        return MetricCardState(
            metric: metric,
            title: metric.displayName,
            value: average.map { value($0, metric, format) } ?? "—",
            unit: unit(metric),
            delta: delta(insight, format: format, range: range),
            coverageShort: "\(recent.daysWithData) of \(recent.daysInPeriod) days",
            statusLine: statusLine,
            isStale: insight.isStale,
            headline: headline,
            isHeadlineMuted: insight.status != .ok,
            detail: detail,
            coverageNote: insight.status == .noData ? nil
                : "Based on \(recent.daysWithData) of \(recent.daysInPeriod) days (\(format.range(recent))). "
                    + "Days with no data are left out, not counted as zero."
                    + " Today is shown separately and isn't included in comparisons.",
            stats: stats(insight, range: range, format: format),
            chart: chartDays.contains { $0.value != nil } ? chartDays.map { point($0, metric: metric, format: format) } : [],
            targetLine: metric == .sleep ? InsightEngine.sleepTargetHours : nil,
            targetLabel: metric == .sleep ? "\(Int(InsightEngine.sleepTargetHours))h goal" : nil,
            averageLine: average,
            averageLabel: average.map { "Avg \(value($0, metric, format))" },
            chartIncludesZero: metric != .restingHeartRate
        )
    }

    private static func value(_ value: Double, _ metric: HealthMetric, _ format: DisplayFormatter) -> String {
        switch metric {
        case .steps, .restingHeartRate: format.int(value)
        case .sleep: format.hours(value)
        }
    }

    private static func unit(_ metric: HealthMetric) -> String {
        switch metric {
        case .steps: "steps / day"
        case .sleep: "avg asleep"
        case .restingHeartRate: "bpm resting"
        }
    }

    /// Match the displayed endpoints; product thresholds only select summary stories.
    private static func displayedChange(_ insight: MetricInsight) -> Double? {
        guard insight.change != nil, let current = insight.recent.average, let prior = insight.prior.average else { return nil }
        if insight.metric == .sleep {
            return ((current * 60).rounded() - (prior * 60).rounded()) / 60
        }
        return current.rounded() - prior.rounded()
    }

    private static func stepChangeText(_ change: Double, prior: Double, format: DisplayFormatter) -> String {
        // A zero baseline has no percentage change. Tiny percentages are clearer as counts.
        guard prior.rounded() > 0, abs(change / prior.rounded() * 100) >= 1 else {
            return "\(format.int(abs(change))) steps/day"
        }
        return "\(format.int(abs(change / prior.rounded() * 100)))%"
    }

    private static func delta(_ insight: MetricInsight, format: DisplayFormatter, range: TimeRange) -> MetricCardState.Delta? {
        guard let change = displayedChange(insight), let prior = insight.prior.average else { return nil }
        if change == 0 {
            return .init(direction: .flat, text: "Same", accessibilityText: "The same displayed average as \(range.previousLabel)")
        }
        let direction: MetricCardState.Delta.Direction = change > 0 ? .up : .down
        let text: String = switch insight.metric {
        case .steps: stepChangeText(change, prior: prior, format: format)
        case .sleep: format.hours(abs(change))
        case .restingHeartRate: "\(format.int(abs(change))) bpm"
        }
        return .init(
            direction: direction,
            text: text,
            accessibilityText: "\(direction == .up ? "Up" : "Down") \(text) from \(range.previousLabel)"
        )
    }

    private static func stats(_ insight: MetricInsight, range: TimeRange, format: DisplayFormatter) -> [MetricCardState.Stat] {
        let metric = insight.metric
        func avg(_ stats: PeriodStats) -> String {
            stats.isSufficient ? stats.average.map { value($0, metric, format) } ?? "—" : "—"
        }
        var rows = [
            MetricCardState.Stat(label: "Average, \(range.currentLabel)", value: avg(insight.recent)),
            MetricCardState.Stat(label: "Average, \(range.previousLabel)", value: avg(insight.prior)),
            MetricCardState.Stat(label: "Days recorded", value: "\(insight.recent.daysWithData) of \(insight.recent.daysInPeriod)"),
        ]
        if let nights = insight.nightsMeetingSleepTarget {
            rows.append(.init(label: "Nights with \(Int(InsightEngine.sleepTargetHours))h+", value: "\(nights) of \(insight.recent.daysWithData)"))
        }
        if let last = insight.lastSampleDate {
            rows.append(.init(label: "Last recorded", value: format.day(last)))
        }
        return rows
    }

    private static func describe(_ insight: MetricInsight, range: TimeRange, format: DisplayFormatter) -> (String, String) {
        guard let average = insight.recent.average else { return ("", "") }
        let comparison: String
        switch (insight.metric, displayedChange(insight), insight.prior.average) {
        case (let metric, 0?, let prior?):
            comparison = "The same displayed average as \(range.previousLabel) (\(value(prior, metric, format)))."
        case (.steps, let change?, let prior?):
            comparison = "\(change > 0 ? "Up" : "Down") \(stepChangeText(change, prior: prior, format: format)) from \(format.int(prior)) in \(range.previousLabel)."
        case (.sleep, let change?, let prior?):
            comparison = "\(format.hours(abs(change))) \(change > 0 ? "more" : "less") than \(range.previousLabel) (\(format.hours(prior)))."
        case (.restingHeartRate, let change?, let prior?):
            comparison = "\(format.int(abs(change))) bpm \(change > 0 ? "higher" : "lower") than \(range.previousLabel) (\(format.int(prior)) bpm)."
        default:
            comparison = "Not enough data from \(range.previousLabel) to compare."
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
            return "The most recent \(name) sample is from \(format.day(lastSample)), before this period."
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
            accessibilityLabel: format.longDay(day.day), accessibilityValue: value,
            calloutDate: format.shortDay(day.day)
        )
    }
}
