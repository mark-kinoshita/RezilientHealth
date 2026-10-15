import Foundation

/// Turns raw sleep samples into hours asleep per night.
///
/// Decisions (tested in SleepAggregatorTests):
/// - Only asleep stages count; "in bed" and "awake" are excluded.
/// - Overlapping samples (e.g. a watch and a phone app both recording the same
///   night) are merged as a union, so the night is not double-counted.
/// - A night belongs to the day you wake up: the window 18:00 the previous
///   day to 18:00 that day. Afternoon naps after 18:00 roll into the next night.
public enum SleepAggregator {
    public static let nightBoundaryHour = 18

    public static func hoursAsleepByDay(
        _ intervals: [SleepInterval],
        days: [Date],
        calendar: Calendar
    ) -> [Date: Double] {
        let merged = mergedAsleepIntervals(intervals)
        var result: [Date: Double] = [:]
        for day in days {
            guard let night = nightWindow(endingOn: day, calendar: calendar) else { continue }
            let seconds = merged.reduce(0.0) { total, interval in
                let start = max(interval.start, night.start)
                let end = min(interval.end, night.end)
                return end > start ? total + end.timeIntervalSince(start) : total
            }
            if seconds > 0 { result[day] = seconds / 3600 }
        }
        return result
    }

    static func nightWindow(endingOn day: Date, calendar: Calendar) -> DateInterval? {
        guard
            let end = calendar.date(bySettingHour: nightBoundaryHour, minute: 0, second: 0, of: day),
            let start = calendar.date(byAdding: .day, value: -1, to: end)
        else { return nil }
        return DateInterval(start: start, end: end)
    }

    static func mergedAsleepIntervals(_ intervals: [SleepInterval]) -> [DateInterval] {
        let asleep = intervals
            .filter { $0.stage.countsAsSleep && $0.end > $0.start }
            .sorted { $0.start < $1.start }
        var merged: [DateInterval] = []
        for interval in asleep {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(DateInterval(start: interval.start, end: interval.end))
            }
        }
        return merged
    }
}

/// Builds the fixed-length daily view the rest of the app works from.
public enum SnapshotBuilder {
    /// 14 completed days plus today: enough for a this-week vs last-week comparison.
    public static let defaultDayCount = 15

    public static func window(now: Date, calendar: Calendar, dayCount: Int = defaultDayCount) -> DateInterval {
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
        dayCount: Int = defaultDayCount
    ) -> HealthSnapshot {
        let window = window(now: now, calendar: calendar, dayCount: dayCount)
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
            access: access,
            series: [
                .steps: series(.steps, raw.dailySteps),
                .sleep: series(.sleep, sleepByDay),
                .restingHeartRate: series(.restingHeartRate, raw.dailyRestingHeartRate),
            ]
        )
    }
}
