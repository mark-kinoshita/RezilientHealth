@testable import RezilientHealth
import Foundation
import Testing

/// Protects how raw health data becomes numbers a member (and the model) sees.
@Suite struct DataInterpretationTests {

    @Test func missingDaysAreExcludedNotCountedAsZero() {
        // 5 of the last 7 completed days recorded 8,000 steps; 2 days have no samples.
        var steps: [Int: Double] = [-7: 8000, -6: 8000, -4: 8000, -2: 8000, -1: 8000]
        for offset in -14 ... -8 { steps[offset] = 6000 }
        let insight = InsightEngine.insights(for: Fixture.snapshot(steps: steps)).first { $0.metric == .steps }!

        #expect(insight.status == .ok)
        #expect(insight.recent.average == 8000)        // zero-filling would give 5,714
        #expect(insight.recent.daysWithData == 5)
        #expect(insight.recent.daysInPeriod == 7)
        #expect(insight.change == 2000)
        #expect(Fixture.context(for: Fixture.snapshot(steps: steps)).metrics["steps"]?.previousPeriod.average == 6000)

        let series = Fixture.snapshot(steps: steps).series(.steps)
        #expect(series.days.first { $0.day == Fixture.day(-5) }?.value == nil)
    }

    @Test func todaysInProgressStepsDoNotDragDownTheAverage() {
        var steps = Dictionary(uniqueKeysWithValues: (-14 ... -1).map { ($0, 10_000.0) })
        steps[0] = 1_200 // it's 2pm
        let snapshot = Fixture.snapshot(steps: steps)
        let insight = InsightEngine.insights(for: snapshot).first { $0.metric == .steps }!

        #expect(snapshot.series(.steps).days.last?.isPartial == true)
        #expect(insight.recent.average == 10_000)
        #expect(insight.recent.lastDay == Fixture.day(-1))
    }

    @Test func tooFewDaysYieldsNoAverageOrComparison() {
        let steps: [Int: Double] = [-3: 12_000, -1: 3_000, -10: 7_000, -9: 7_000, -8: 7_000, -11: 7_000]
        let insight = InsightEngine.insights(for: Fixture.snapshot(steps: steps)).first { $0.metric == .steps }!

        #expect(insight.status == .insufficientData)
        #expect(insight.change == nil)
        #expect(insight.recent.isSufficient == false)
    }

    @Test func noSamplesIsReportedAsUnknownNotInactive() {
        let insights = InsightEngine.insights(for: Fixture.snapshot(access: .requested))
        for insight in insights {
            #expect(insight.status == .noData)
            #expect(insight.recent.average == nil)
            #expect(insight.isStale == false)
        }
        let context = Fixture.context(for: Fixture.snapshot())
        #expect(context.metricsWithData.isEmpty)
        #expect(context.metrics["steps"]?.daily.allSatisfy { $0.value == nil } == true)
        // The model is told null means "no data"; the key must be present.
        #expect(context.jsonString(pretty: false).contains(#"{"date":"\#(context.window.start)","value":null}"#))
    }

    @Test func staleDataIsFlagged() {
        // Only old data: last steps recorded 6 days ago.
        let steps = Dictionary(uniqueKeysWithValues: (-14 ... -6).map { ($0, 9000.0) })
        let snapshot = Fixture.snapshot(steps: steps, latest: [.steps: Fixture.day(-6) + 20 * 3600])
        let insight = InsightEngine.insights(for: snapshot).first { $0.metric == .steps }!

        #expect(insight.isStale)
        #expect(insight.status == .insufficientData) // 2 of last 7 days
    }

    @Test func monthRangeComparesThirtyDaysAndNeedsHalfOfThem() {
        // 14 days of data in the last 30: enough for a week view, not a month.
        let steps = Dictionary(uniqueKeysWithValues: (-14 ... -1).map { ($0, 9000.0) })
        let raw = RawHealthData(
            dailySteps: Dictionary(uniqueKeysWithValues: steps.map { (Fixture.day($0.key), $0.value) }),
            latestSampleDate: [.steps: Fixture.now]
        )
        let month = SnapshotBuilder.build(raw: raw, access: .requested, now: Fixture.now, calendar: Fixture.calendar, range: .month)
        let insight = InsightEngine.insights(for: month).first { $0.metric == .steps }!

        #expect(month.series(.steps).days.count == 61)          // 30 + 30 + today
        #expect(insight.recent.daysInPeriod == 30)
        #expect(insight.recent.daysWithData == 14)
        #expect(insight.recent.minimumDaysWithData == 15)
        #expect(insight.status == .insufficientData)

        let week = InsightEngine.insights(for: Fixture.snapshot(steps: steps)).first { $0.metric == .steps }!
        #expect(week.status == .ok)
    }

    @Test func overlappingSleepSourcesAreMergedAndOnlyAsleepStagesCount() {
        // Night ending Oct 14: in bed 22:30–07:00, watch says asleep 23:00–06:30
        // (7.5h, with a 30-min awake block), a phone app overlaps 23:15–06:00.
        let intervals = [
            SleepInterval(start: Fixture.date(2026, 10, 13, 22, 30), end: Fixture.date(2026, 10, 14, 7), stage: .inBed),
            SleepInterval(start: Fixture.date(2026, 10, 13, 23), end: Fixture.date(2026, 10, 14, 2), stage: .asleepCore),
            SleepInterval(start: Fixture.date(2026, 10, 14, 2), end: Fixture.date(2026, 10, 14, 2, 30), stage: .awake),
            SleepInterval(start: Fixture.date(2026, 10, 14, 2, 30), end: Fixture.date(2026, 10, 14, 6, 30), stage: .asleepDeep),
            SleepInterval(start: Fixture.date(2026, 10, 13, 23, 15), end: Fixture.date(2026, 10, 14, 1), stage: .asleepUnspecified),
            SleepInterval(start: Fixture.date(2026, 10, 14, 3), end: Fixture.date(2026, 10, 14, 6), stage: .asleepUnspecified),
        ]
        let hours = SleepAggregator.hoursAsleepByDay(
            intervals, days: [Fixture.day(-2), Fixture.day(-1), Fixture.day(0)], calendar: Fixture.calendar
        )

        #expect(hours[Fixture.day(-1)] == 7.0)   // 3h + 4h; naive sum would be ~11.75h
        #expect(hours[Fixture.day(-2)] == nil)   // attributed to the wake-up day only
        #expect(hours[Fixture.day(0)] == nil)
    }
}
