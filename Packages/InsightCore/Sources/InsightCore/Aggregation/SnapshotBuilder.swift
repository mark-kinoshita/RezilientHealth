import Foundation

/// Builds the fixed-length daily view the rest of the app works from.
public enum SnapshotBuilder {
    /// Two full periods plus today: the current period, the one before it for
    /// comparison, and today's in-progress values.
    public static func window(now: Date, calendar: Calendar, range: TimeRange = .week) -> DateInterval {
        let dayCount = range.days * 2 + 1
        let today = calendar.startOfDay(for: now)
        let first = calendar.date(byAdding: .day, value: -(dayCount - 1), to: today)!
        return DateInterval(start: first, end: now)
    }

    public static func days(in window: DateInterval, calendar: Calendar) -> [Date] {
        var days: [Date] = []
        var day = calendar.startOfDay(for: window.start)
        while day < window.end {
            days.append(day)
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return days
    }

    public static func build(
        raw: RawHealthData,
        access: HealthAccessState,
        now: Date,
        calendar: Calendar,
        range: TimeRange = .week
    ) -> HealthSnapshot {
        let window = window(now: now, calendar: calendar, range: range)
        let days = days(in: window, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        let sleepByDay = SleepAggregator.hoursAsleepByDay(raw.sleepIntervals, days: days, calendar: calendar)

        func series(_ metric: HealthMetric, _ values: [Date: Double]) -> MetricSeries {
            MetricSeries(
                metric: metric,
                days: days.map { day in
                    DailyValue(
                        day: day,
                        value: values[day],
                        isPartial: day == today && !metric.todayIsComplete
                    )
                },
                lastSampleDate: raw.latestSampleDate[metric]
            )
        }

        return HealthSnapshot(
            generatedAt: now,
            calendar: calendar,
            window: window,
            range: range,
            access: access,
            series: [
                .steps: series(.steps, raw.dailySteps),
                .sleep: series(.sleep, sleepByDay),
                .restingHeartRate: series(.restingHeartRate, raw.dailyRestingHeartRate),
            ]
        )
    }
}
