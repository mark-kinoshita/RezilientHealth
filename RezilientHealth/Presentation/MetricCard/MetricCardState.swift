import Foundation

/// Everything the dashboard tile and the metric detail screen render, already
/// worded and formatted. The tile uses the short fields; detail uses the rest.
public struct MetricCardState: Sendable, Equatable, Identifiable {
    public struct ChartPoint: Sendable, Equatable, Identifiable {
        public let day: Date
        /// `nil` renders as an explicit "no data" column, never a zero bar.
        public let value: Double?
        public let isPartial: Bool
        public let accessibilityLabel: String
        public let accessibilityValue: String
        /// Callout text when the member scrubs to this day: "Wed, Oct 15".
        public let calloutDate: String

        public var id: Date { day }
    }

    /// Change versus the previous period. Shown neutrally: whether "up" is
    /// good depends on the metric and the person.
    public struct Delta: Sendable, Equatable {
        public enum Direction: Sendable, Equatable { case up, down, flat }
        public let direction: Direction
        /// "35%", "5,000 steps/day", "25m", "3 bpm", or "Same"
        public let text: String
        public let accessibilityText: String
    }

    public struct Stat: Sendable, Equatable, Identifiable {
        public let label: String
        public let value: String
        public var id: String { label }
    }

    public let metric: HealthMetric
    public let title: String

    // Tile
    /// "8,374", "7h 10m", "58", or "—" when there's no usable average.
    public let value: String
    /// "steps / day", "avg asleep", "bpm resting"
    public let unit: String
    public let delta: Delta?
    /// "5 of 7 days"
    public let coverageShort: String
    /// One short line instead of a number when status isn't ok.
    public let statusLine: String?
    public let isStale: Bool

    // Detail
    public let headline: String
    public let isHeadlineMuted: Bool
    public let detail: String
    /// Hidden when there's no data at all (a "0 of 7 days" line adds nothing).
    public let coverageNote: String?
    public let stats: [Stat]
    /// Current period plus today; empty when there's nothing to chart.
    public let chart: [ChartPoint]
    /// The same completed days used for the average, excluding today for every metric.
    public var comparisonChart: [ChartPoint] { Array(chart.dropLast()) }
    /// Sleep draws a dashed target line at this value.
    public let targetLine: Double?
    public let targetLabel: String?
    /// The current period's average, drawn as a reference line on the detail chart.
    public let averageLine: Double?
    /// "Avg 8,392"
    public let averageLabel: String?
    /// Resting heart rate reads better without a zero baseline.
    public let chartIncludesZero: Bool

    public var id: HealthMetric { metric }
}
