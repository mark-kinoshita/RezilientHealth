import Foundation
import InsightCore
import Testing
@testable import InsightPresentation

/// Protects the wording members see: coverage is always stated, missing data
/// is never described as inactivity, and the model quotes dashboard figures.
@Suite struct MetricCardCopyTests {
    func card(_ snapshot: HealthSnapshot, _ metric: HealthMetric) -> MetricCardState {
        let insight = InsightEngine.insights(for: snapshot).first { $0.metric == metric }!
        return MetricCardPresenter.card(for: insight, series: snapshot.series(metric), range: snapshot.range, access: snapshot.access, calendar: Fixture.calendar)
    }

    @Test func coverageIsStatedAndGapsAreExplicitInTheChart() {
        var steps: [Int: Double] = [-7: 8000, -6: 8000, -4: 8000, -2: 8000, -1: 8000, 0: 1200]
        for offset in -14 ... -8 { steps[offset] = 6000 }
        let card = card(Fixture.snapshot(steps: steps), .steps)

        #expect(card.headline == "Averaging 8,000 steps a day")
        #expect(card.value == "8,000" && card.unit == "steps / day")
        #expect(card.delta?.direction == .up && card.delta?.text == "33%")
        #expect(card.coverageShort == "5 of 7 days")
        #expect(card.averageLine == 8000 && card.averageLabel == "Avg 8,000")
        #expect(card.coverageNote?.contains("Based on 5 of 7 days") == true)
        #expect(card.coverageNote?.contains("not counted as zero") == true)
        let missing = card.chart.first { $0.day == Fixture.day(-5) }!
        #expect(missing.value == nil && missing.accessibilityValue == "No data recorded")
        #expect(card.chart.last?.accessibilityValue == "1,200 steps so far today")
    }

    @Test func zeroStepBaselineShowsAnAbsoluteIncreaseAndBothZerosStayFlat() {
        for current in [0.0, 5000.0] {
            let steps = Dictionary(uniqueKeysWithValues: (-14 ... -1).map { ($0, $0 < -7 ? 0.0 : current) })
            let snapshot = Fixture.snapshot(steps: steps)
            let presented = card(snapshot, .steps)
            let answerRow = AnswerMetricPresenter.rows(keys: ["steps"], context: Fixture.context(for: snapshot)).first!
            #expect(presented.delta?.direction == (current == 0 ? .flat : .up))
            #expect(presented.delta?.direction == answerRow.direction)
            if current > 0 {
                #expect(presented.delta?.text == "5,000 steps/day")
                #expect(presented.detail.contains("Up 5,000 steps/day from 0"))
                #expect(!presented.detail.contains("%"))
            }
        }
    }

    @Test func smallChangesHaveTheSameDirectionInDetailAndChat() {
        let steps = Dictionary(uniqueKeysWithValues: (-14 ... -1).map { ($0, $0 < -7 ? 8000.0 : 8200.0) })
        let heartRate = Dictionary(uniqueKeysWithValues: (-14 ... -1).map { ($0, $0 < -7 ? 58.0 : 58.6) })
        let sleep = (-14 ... -1).map { day in
            SleepInterval(start: Fixture.day(day), end: Fixture.day(day).addingTimeInterval(day < -7 ? 8 * 3600 : 7 * 3600 + 50 * 60), stage: .asleepCore)
        }
        let snapshot = Fixture.snapshot(steps: steps, restingHR: heartRate, sleep: sleep)
        let rows = AnswerMetricPresenter.rows(keys: HealthMetric.allCases.map(\.rawValue), context: Fixture.context(for: snapshot))
        for row in rows {
            #expect(card(snapshot, row.metric).delta?.direction == row.direction)
            #expect(row.direction != .flat)
        }
        #expect(card(snapshot, .sleep).delta?.text == "10m")
        #expect(card(snapshot, .restingHeartRate).delta?.text == "1 bpm")
    }

    @Test func minuteBoundaryRoundingMatchesTheDashboardAndChat() {
        let sleep = (-14 ... -1).map { day in
            SleepInterval(start: Fixture.day(day), end: Fixture.day(day).addingTimeInterval((day < -7 ? 8 : 7.008) * 3600), stage: .asleepCore)
        }
        let snapshot = Fixture.snapshot(sleep: sleep)
        let context = Fixture.context(for: snapshot)
        let row = AnswerMetricPresenter.rows(keys: ["sleep"], context: context).first!
        #expect(card(snapshot, .sleep).value == "7h 0m")
        #expect(row.value == card(snapshot, .sleep).value)
        #expect(row.changeText == card(snapshot, .sleep).delta?.text)
    }

    @Test func overviewChartsUseTheExactCompletedComparisonWindowForEveryMetricAndRange() {
        let steps = Dictionary(uniqueKeysWithValues: (-180 ... 0).map { (Fixture.day($0), $0 == 0 ? 99999.0 : 8000.0) })
        let heartRate = Dictionary(uniqueKeysWithValues: (-180 ... 0).map { (Fixture.day($0), 60.0) })
        let sleep = (-180 ... 0).map { day in
            SleepInterval(start: Fixture.day(day), end: Fixture.day(day).addingTimeInterval((day == 0 ? 10 : 7) * 3600), stage: .asleepCore)
        }
        let raw = RawHealthData(dailySteps: steps, sleepIntervals: sleep, dailyRestingHeartRate: heartRate,
                                latestSampleDate: [.steps: Fixture.now, .sleep: Fixture.now, .restingHeartRate: Fixture.now])
        for range in TimeRange.allCases {
            let snapshot = SnapshotBuilder.build(raw: raw, access: .requested, now: Fixture.now, calendar: Fixture.calendar, range: range)
            for metric in HealthMetric.allCases {
                let presented = card(snapshot, metric)
                #expect(presented.comparisonChart.count == range.days)
                #expect(presented.comparisonChart.first?.day == Fixture.day(-range.days))
                #expect(presented.comparisonChart.last?.day == Fixture.day(-1))
                #expect(presented.chart.last?.day == Fixture.day(0))
                let values = presented.comparisonChart.compactMap(\.value)
                #expect(values.reduce(0, +) / Double(values.count) == presented.averageLine)
            }
        }
    }

    @Test func noDataNeverReadsAsInactivity() {
        let card = card(Fixture.snapshot(access: .requested), .steps)
        #expect(card.isHeadlineMuted)
        #expect(card.detail.contains("doesn't mean nothing happened"))
        #expect(card.coverageNote == nil)
        #expect(card.chart.isEmpty)
    }

    @Test func sparseAndStaleDataSaySo() {
        let steps = Dictionary(uniqueKeysWithValues: (-14 ... -6).map { ($0, 9000.0) })
        let card = card(Fixture.snapshot(steps: steps, latest: [.steps: Fixture.day(-6) + 20 * 3600]), .steps)
        #expect(card.headline == "Not enough steps data in the last 7 days")
        #expect(card.value == "—" && card.statusLine == "Not enough data")
        #expect(card.isStale)
        #expect(card.detail.contains("Last recorded"))
    }

    @Test func sufficientButOldDataKeepsItsAverageAndFreshnessWarning() {
        let steps = Dictionary(uniqueKeysWithValues: (-14 ... -3).map { ($0, 9000.0) })
        let presented = card(Fixture.snapshot(steps: steps, latest: [.steps: Fixture.day(-3)]), .steps)
        #expect(presented.value == "9,000")
        #expect(presented.statusLine == nil)
        #expect(presented.isStale)
        #expect(presented.detail.contains("Last recorded"))
    }

    @Test func modelContextQuotesTheSameFiguresAsTheDashboard() {
        // 7h 10m average. Rounding to 0.1h in the context once made the model
        // say "7h 12m" while the dashboard said "7h 10m".
        let nights = (-6...0).map { offset -> SleepInterval in
            let wake = Fixture.day(offset) + 6 * 3600
            return SleepInterval(start: wake - (7 * 3600 + 10 * 60), end: wake, stage: .asleepCore)
        }
        let snapshot = Fixture.snapshot(sleep: nights)
        let context = Fixture.context(for: snapshot)

        #expect(card(snapshot, .sleep).headline == "Averaging 7h 10m asleep")
        // Last night's sleep is complete, so the note must not claim today is excluded.
        #expect(card(snapshot, .sleep).coverageNote?.contains("Today is still in progress") == false)
        #expect(DisplayFormatter(calendar: Fixture.calendar).hours(context.metrics["sleep"]!.currentPeriod.average!) == "7h 10m")
    }
}
