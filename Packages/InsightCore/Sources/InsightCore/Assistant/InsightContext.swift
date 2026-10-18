import Foundation

/// The exact structured context sent to the model. It holds daily aggregates
/// and the app's own computed summaries, never raw samples, device names, or
/// identity. The model is told to use these numbers rather than recompute.
public struct InsightContext: Codable, Sendable, Equatable {
    public struct Window: Codable, Sendable, Equatable {
        public let start: String
        public let end: String
        public let timezone: String
        public let periodDays: Int
        public let note: String
    }

    public struct Day: Codable, Sendable, Equatable {
        public let date: String
        /// `null` = no data recorded that day (not zero).
        public let value: Double?
        public let partial: Bool?

        enum CodingKeys: String, CodingKey { case date, value, partial }

        public init(date: String, value: Double?, partial: Bool?) {
            self.date = date
            self.value = value
            self.partial = partial
        }

        // Synthesized encoding omits nil keys; the prompt promises the model an
        // explicit `"value": null` for days without data, so encode it.
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(date, forKey: .date)
            try container.encode(value, forKey: .value)
            try container.encodeIfPresent(partial, forKey: .partial)
        }
    }

    public struct Period: Codable, Sendable, Equatable {
        public let start: String?
        public let end: String?
        public let average: Double?
        public let daysWithData: Int
        public let daysInPeriod: Int
        public let sufficient: Bool
    }

    public struct Metric: Codable, Sendable, Equatable {
        public let unit: String
        public let status: MetricInsight.Status
        public let lastSampleAt: String?
        public let stale: Bool
        public let currentPeriod: Period
        public let previousPeriod: Period
        public let daily: [Day]
    }

    public let generatedAt: String
    public let window: Window
    public let healthAccess: HealthAccessState
    public let accessNote: String
    public let metrics: [String: Metric]
    public let notTrackedInThisApp: [String]

    public static let notTracked = [
        "heart_rate_variability", "workouts", "calories", "blood_pressure",
        "blood_glucose", "weight", "nutrition", "menstrual_cycle", "medications", "mood_or_stress",
    ]

    public func jsonString(pretty: Bool = true) -> String {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Metrics with at least one recorded day in the window.
    public var metricsWithData: Set<HealthMetric> {
        Set(metrics.compactMap { key, value in
            value.status == .noData ? nil : HealthMetric(rawValue: key)
        })
    }
}

public enum InsightContextBuilder {
    /// Round the way the dashboard displays each metric, so the model quotes
    /// the same figures: whole steps and bpm; sleep hours to 2 decimals
    /// (accurate to the minute).
    static func rounded(_ value: Double, for metric: HealthMetric) -> Double {
        switch metric {
        case .steps, .restingHeartRate: value.rounded()
        case .sleep: (value * 100).rounded() / 100
        }
    }

    public static func build(snapshot: HealthSnapshot, insights: [MetricInsight]) -> InsightContext {
        let calendar = snapshot.calendar
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = calendar
        dayFormatter.timeZone = calendar.timeZone
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let timestamp = ISO8601DateFormatter()
        timestamp.timeZone = calendar.timeZone

        func period(_ stats: PeriodStats, _ metric: HealthMetric) -> InsightContext.Period {
            InsightContext.Period(
                start: stats.firstDay.map(dayFormatter.string),
                end: stats.lastDay.map(dayFormatter.string),
                average: stats.average.map { rounded($0, for: metric) },
                daysWithData: stats.daysWithData,
                daysInPeriod: stats.daysInPeriod,
                sufficient: stats.isSufficient
            )
        }

        var metrics: [String: InsightContext.Metric] = [:]
        for insight in insights {
            let series = snapshot.series(insight.metric)
            metrics[insight.metric.rawValue] = InsightContext.Metric(
                unit: insight.metric.unit,
                status: insight.status,
                lastSampleAt: series.lastSampleDate.map(timestamp.string),
                stale: insight.isStale,
                currentPeriod: period(insight.recent, insight.metric),
                previousPeriod: period(insight.prior, insight.metric),
                daily: series.days.map {
                    InsightContext.Day(
                        date: dayFormatter.string(from: $0.day),
                        value: $0.value.map { rounded($0, for: insight.metric) },
                        partial: $0.isPartial ? true : nil
                    )
                }
            )
        }

        let accessNote: String = switch snapshot.access {
        case .unavailable: "Health data is not available on this device."
        case .notDetermined: "The member has not connected Apple Health yet."
        case .requested: "Access was requested. The platform does not reveal whether read access was denied, so a metric with no data may be switched off, not worn, or truly absent."
        }

        return InsightContext(
            generatedAt: timestamp.string(from: snapshot.generatedAt),
            window: .init(
                start: dayFormatter.string(from: snapshot.window.start),
                end: dayFormatter.string(from: snapshot.generatedAt),
                timezone: calendar.timeZone.identifier,
                periodDays: snapshot.range.days,
                note: "The member is viewing \(snapshot.range.currentLabel), compared with \(snapshot.range.previousLabel). current_period and previous_period summarize those. Daily values are calendar-day totals (sleep: the night ending that morning). Today is in progress for steps and resting heart rate and is not in either period."
            ),
            healthAccess: snapshot.access,
            accessNote: accessNote,
            metrics: metrics,
            notTrackedInThisApp: InsightContext.notTracked
        )
    }
}
