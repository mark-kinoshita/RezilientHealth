import Foundation

public struct PatternSummaryState: Sendable, Equatable {
    public struct DailySample: Sendable, Equatable, Identifiable {
        public let day: Date
        public let value: Double?
        public var id: Date { day }
    }

    public struct Evidence: Sendable, Equatable, Identifiable {
        public let metric: HealthMetric
        /// Existing full sentence retained for accessible description and tests.
        public let text: String
        public let coverage: String
        public let coverageShort: String
        public let previousValue: String
        public let currentValue: String
        public let changeText: String
        public let previousRange: String
        public let currentRange: String
        /// Completed daily samples only; nil entries stay visible as gaps.
        public let dailyValues: [DailySample]
        public var id: HealthMetric { metric }
    }

    public let title: String
    public let explanation: String
    public let evidence: [Evidence]
    public let supportingTitle: String?
    public let supportingText: String?
    public let question: String

    static func build(snapshot: HealthSnapshot, insights: [MetricInsight]) -> Self {
        let facts = PatternSummary.build(snapshot: snapshot, insights: insights)
        let format = DisplayFormatter(calendar: snapshot.calendar)
        let changes = facts.changes

        func phrase(for change: PatternSummary.Change) -> String {
            let direction = change.difference < 0 ? "dipped" : "rose"
            return switch change.metric {
            case .steps: "Activity \(direction)"
            case .sleep: "Sleep \(direction)"
            case .restingHeartRate: "Resting heart rate \(direction)"
            }
        }

        let title: String
        let explanation: String
        if changes.count >= 2 {
            title = changes.prefix(2).map(phrase).joined(separator: ". ") + "."
            explanation = snapshot.range == .week
                ? "Compared with the previous week."
                : "Compared with \(snapshot.range.previousLabel)."
        } else if let change = changes.first {
            title = phrase(for: change) + "."
            explanation = "Compared with \(snapshot.range.previousLabel)."
        } else if facts.sleepSpread != nil {
            title = "Your sleep varied across nights."
            explanation = "One average can hide that variation."
        } else if facts.comparableMetrics > 0 {
            title = "No large shifts in comparable data."
            explanation = "\(facts.comparableMetrics) of 3 metrics had enough fresh data to compare."
        } else {
            title = "Not enough data for a comparison yet."
            explanation = "We need recordings on at least half the days in both periods."
        }

        let evidence = changes.prefix(2).map { change in
            let displayedDifference: Double = change.metric == .sleep
                ? ((change.current * 60).rounded() - (change.previous * 60).rounded()) / 60
                : change.current.rounded() - change.previous.rounded()
            let amount: String = switch change.metric {
            case .steps: "\(format.int(abs(displayedDifference))) \(change.difference < 0 ? "fewer" : "more") steps per day"
            case .sleep: "\(format.hours(abs(displayedDifference))) \(change.difference < 0 ? "less" : "more") sleep per night"
            case .restingHeartRate: "\(format.int(abs(displayedDifference))) bpm \(change.difference < 0 ? "lower" : "higher") on average"
            }
            func value(_ number: Double) -> String {
                change.metric == .sleep ? format.hours(number) : format.int(number)
            }
            let changeText: String = switch change.metric {
            case .steps: "\(change.difference < 0 ? "−" : "+")\(format.int(abs(displayedDifference))) / day"
            case .sleep: "\(change.difference < 0 ? "−" : "+")\(format.hours(abs(displayedDifference)))"
            case .restingHeartRate: "\(change.difference < 0 ? "−" : "+")\(format.int(abs(displayedDifference))) bpm"
            }
            let insight = insights.first { $0.metric == change.metric }
            return Evidence(
                metric: change.metric,
                text: "About \(amount) · \(value(change.previous)) → \(value(change.current))",
                coverage: "Recorded days: \(change.recentDays)/\(change.periodDays) current · \(change.priorDays)/\(change.periodDays) previous. Missing days excluded.",
                coverageShort: "\(change.recentDays)/\(change.periodDays) \(change.metric == .sleep ? "nights" : "days")",
                previousValue: value(change.previous),
                currentValue: value(change.current),
                changeText: changeText,
                previousRange: insight.map { format.range($0.prior) } ?? snapshot.range.previousLabel,
                currentRange: insight.map { format.range($0.recent) } ?? snapshot.range.currentLabel,
                dailyValues: InsightEngine.currentDays(of: snapshot.series(change.metric), range: snapshot.range).map { DailySample(day: $0.day, value: $0.value) }
            )
        }
        let spread = facts.sleepSpread
        return Self(
            title: title,
            explanation: explanation,
            evidence: evidence,
            supportingTitle: spread == nil ? nil : "Sleep range",
            supportingText: spread.map {
                "\(format.hours($0.shortest))–\(format.hours($0.longest)) across \($0.recordedNights) recorded nights"
            },
            question: changes.count >= 2
                ? "What changed together over \(snapshot.range.currentLabel)?"
                : changes.first.map { "What do you notice about my \($0.metric.displayName.lowercased()) over \(snapshot.range.currentLabel)?" }
                    ?? (spread == nil ? "What can you tell me from the available data over \(snapshot.range.currentLabel)?" : "How much did my sleep vary over \(snapshot.range.currentLabel)?")
        )
    }
}
