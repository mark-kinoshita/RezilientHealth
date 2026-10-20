import Foundation

/// Every displayed figure comes from the request's captured on-device context.
/// No number, date or coverage value is accepted from a model response.
public struct AnswerMetricRow: Sendable, Equatable, Identifiable {
    public let metric: HealthMetric
    public let value: String
    public let previous: String
    public let changeText: String?
    public let direction: MetricCardState.Delta.Direction?
    public let coverage: String
    public let isStale: Bool
    public let currentRange: String
    public let previousRange: String?
    public let notes: [String]
    public let canExplore: Bool
    public var id: HealthMetric { metric }
}

public struct AnswerFollowUp: Sendable, Equatable, Identifiable {
    public let metric: HealthMetric
    public let title: String
    public let question: String
    public var id: HealthMetric { metric }
}

enum AnswerMetricPresenter {
    static func rows(keys: [String], context: InsightContext) -> [AnswerMetricRow] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: context.window.timezone) ?? TimeZone(secondsFromGMT: 0)!
        let format = DisplayFormatter(calendar: calendar)
        let parser = DateFormatter()
        parser.calendar = calendar
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = calendar.timeZone
        parser.dateFormat = "yyyy-MM-dd"
        func range(_ period: InsightContext.Period) -> String? {
            guard let first = period.start.flatMap(parser.date), let last = period.end.flatMap(parser.date) else { return nil }
            return "\(format.day(first))–\(format.day(last))"
        }
        var seen = Set<String>()
        return keys.compactMap { key in
            guard seen.insert(key).inserted, let metric = HealthMetric(rawValue: key),
                  let data = context.metrics[key], data.status != .noData else { return nil }
            let current = data.currentPeriod
            let prior = data.previousPeriod
            func value(_ number: Double) -> String {
                switch metric {
                case .steps: "\(format.int(number))/day"
                case .sleep: format.hours(number)
                case .restingHeartRate: "\(format.int(number)) bpm"
                }
            }
            let average = current.sufficient ? current.average : nil
            let priorAverage = prior.sufficient ? prior.average : nil
            var direction: MetricCardState.Delta.Direction?
            var changeText: String?
            if let average, let priorAverage {
                let difference = average - priorAverage
                direction = difference == 0 ? .flat : difference > 0 ? .up : .down
                // Sleep differences are shown to the same minute as the two
                // displayed endpoints. Other metrics use a neutral direction.
                if metric == .sleep {
                    let minutes = Int((average * 60).rounded()) - Int((priorAverage * 60).rounded())
                    direction = minutes == 0 ? .flat : minutes > 0 ? .up : .down
                    changeText = minutes == 0 ? "Same" : format.hours(Double(abs(minutes)) / 60)
                } else if difference == 0 {
                    changeText = "Same"
                }
            }
            let noun = metric == .sleep ? "nights" : "days"
            var notes: [String] = []
            let missing = current.daysInPeriod - current.daysWithData
            if missing > 0 {
                notes.append("\(metric.displayName): \(current.daysWithData) of \(current.daysInPeriod) \(noun) recorded. Missing \(noun) are excluded, not counted as zero.")
            }
            if !current.sufficient {
                notes.append("\(metric.displayName): at least half the days need recordings before an average is shown.")
            }
            if !prior.sufficient {
                notes.append("\(metric.displayName): \(prior.daysWithData) of \(prior.daysInPeriod) \(noun) recorded in the earlier period; no comparison is shown.")
            }
            if data.stale {
                notes.append("\(metric.displayName): the last recording is over forty-eight hours old. This may not reflect recent days.")
            }
            return AnswerMetricRow(
                metric: metric,
                value: average.map(value) ?? "Not enough data",
                previous: average == nil ? "No reliable average yet" : (priorAverage.map { value($0) + " before" } ?? "Not enough earlier data"),
                changeText: changeText, direction: direction,
                coverage: "\(current.daysWithData)/\(current.daysInPeriod) \(noun)",
                isStale: data.stale,
                currentRange: range(current) ?? "Last \(context.window.periodDays) completed days",
                previousRange: range(prior),
                notes: notes,
                canExplore: average != nil && !data.stale
            )
        }
    }
}
