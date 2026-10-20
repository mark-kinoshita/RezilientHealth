import Foundation

/// Facts selected for the dashboard's narrative. No LLM or medical inference.
public struct PatternSummary: Sendable, Equatable, Codable {
    public struct Change: Sendable, Equatable, Codable {
        public let metric: HealthMetric
        public let current: Double
        public let previous: Double
        public let difference: Double
        public let recentDays: Int
        public let priorDays: Int
        public let periodDays: Int
        /// Size relative to a product selection threshold, not clinical importance.
        public let selectionScore: Double
    }

    public struct SleepSpread: Sendable, Equatable, Codable {
        public let shortest: Double
        public let longest: Double
        public let recordedNights: Int
        public let periodDays: Int
    }

    /// Ranked by relative change size; ties follow HealthMetric's stable order.
    public let changes: [Change]
    public let comparableMetrics: Int
    public let sleepSpread: SleepSpread?

    public static func build(snapshot: HealthSnapshot, insights: [MetricInsight]) -> Self {
        let comparable = insights.filter {
            $0.status == .ok && !$0.isStale && $0.prior.isSufficient && $0.change != nil
        }
        let changes = comparable.compactMap { insight -> Change? in
            guard let current = insight.recent.average,
                  let previous = insight.prior.average, let difference = insight.change else { return nil }
            // Product heuristics to avoid narrating ordinary small fluctuations:
            // steps >=20% AND >=1,000/day; sleep >=30 min; resting HR >=3 bpm.
            let threshold: Double = switch insight.metric {
            case .steps: max(abs(previous) * 0.2, 1000)
            case .sleep: 0.5
            case .restingHeartRate: 3
            }
            let score = abs(difference) / threshold
            guard score >= 1 else { return nil }
            return Change(metric: insight.metric, current: current, previous: previous,
                          difference: difference, recentDays: insight.recent.daysWithData,
                          priorDays: insight.prior.daysWithData, periodDays: snapshot.range.days,
                          selectionScore: score)
        }.sorted {
            if $0.selectionScore == $1.selectionScore {
                return MetricCatalog.enabled.firstIndex(of: $0.metric)! < MetricCatalog.enabled.firstIndex(of: $1.metric)!
            }
            return $0.selectionScore > $1.selectionScore
        }

        var spread: SleepSpread?
        if let sleep = insights.first(where: { $0.metric == .sleep }), sleep.status == .ok, !sleep.isStale {
            let nights = InsightEngine.currentDays(of: snapshot.series(.sleep), range: snapshot.range).compactMap(\.value)
            if let shortest = nights.min(), let longest = nights.max(), longest - shortest >= 1 {
                spread = SleepSpread(shortest: shortest, longest: longest,
                                     recordedNights: nights.count, periodDays: snapshot.range.days)
            }
        }
        return Self(changes: changes, comparableMetrics: comparable.count, sleepSpread: spread)
    }
}
