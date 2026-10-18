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
