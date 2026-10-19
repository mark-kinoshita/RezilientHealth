import Foundation
import Testing
@testable import InsightCore

@Suite struct PatternSummaryTests {
    private func summary(_ snapshot: HealthSnapshot) -> PatternSummary {
        PatternSummary.build(snapshot: snapshot, insights: InsightEngine.insights(for: snapshot))
    }

    @Test func combinedChangesUseTheSameDatesAndExcludeToday() {
        var steps = Dictionary(uniqueKeysWithValues: (-14 ... -1).map { ($0, $0 < -7 ? 8000.0 : 5000.0) })
        steps[0] = 99_000
        let hr = Dictionary(uniqueKeysWithValues: (-14 ... -1).map { ($0, $0 < -7 ? 60.0 : 64.0) })
        let sleep = (-14 ... 0).map { offset in
            SleepInterval(start: Fixture.day(offset).addingTimeInterval(-3600),
                          end: Fixture.day(offset).addingTimeInterval((offset < -7 ? 7 : 5) * 3600), stage: .asleepCore)
        }
        let snapshot = Fixture.snapshot(steps: steps, restingHR: hr, sleep: sleep)
        let facts = summary(snapshot)
        #expect(Set(facts.changes.map(\.metric)) == Set(HealthMetric.allCases))
        #expect(Fixture.context(for: snapshot).dashboardPatterns == facts)
        #expect(Fixture.context(for: snapshot).jsonString().contains("dashboard_patterns"))
        #expect(facts.changes.first?.metric == .sleep)
        #expect(facts.changes.first?.difference == -2)
        #expect(facts.changes.first { $0.metric == .steps }?.difference == -3000)
        for insight in InsightEngine.insights(for: snapshot) {
            #expect(insight.recent.firstDay == Fixture.day(-7))
            #expect(insight.recent.lastDay == Fixture.day(-1))
            #expect(insight.prior.firstDay == Fixture.day(-14))
            #expect(insight.prior.lastDay == Fixture.day(-8))
        }
    }

    @Test func gapsAreExcludedAndBothPeriodsNeedCoverage() {
        var steps: [Int: Double] = [-7: 0, -6: 0, -5: 0, -4: 0]
        for offset in -14 ... -8 { steps[offset] = 8000 }
        let facts = summary(Fixture.snapshot(steps: steps))
        #expect(facts.changes.first?.current == 0) // Recorded zero is real data.
        #expect(facts.changes.first?.recentDays == 4)
        steps[-4] = nil
        #expect(summary(Fixture.snapshot(steps: steps)).changes.isEmpty)
        steps[-4] = 0
        for offset in -14 ... -11 { steps[offset] = nil }
        #expect(summary(Fixture.snapshot(steps: steps)).changes.isEmpty)
    }

    @Test func staleDataAndSmallChangesDoNotGenerateAStory() {
        let steps = Dictionary(uniqueKeysWithValues: (-14 ... -1).map { ($0, $0 < -7 ? 8000.0 : 5000.0) })
        #expect(summary(Fixture.snapshot(steps: steps, latest: [.steps: Fixture.day(-4)])).changes.isEmpty)
        let small = Dictionary(uniqueKeysWithValues: (-14 ... -1).map { ($0, $0 < -7 ? 8000.0 : 7900.0) })
        #expect(summary(Fixture.snapshot(steps: small)).changes.isEmpty)
        #expect(summary(Fixture.snapshot(steps: small)).comparableMetrics == 1)
    }

    @Test func zeroBaselineHasAnAbsoluteThresholdInsteadOfDividingByZero() {
        let steps = Dictionary(uniqueKeysWithValues: (-14 ... -1).map { ($0, $0 < -7 ? 0.0 : 1500.0) })
        let change = summary(Fixture.snapshot(steps: steps)).changes.first
        #expect(change?.difference == 1500)
        #expect(change?.selectionScore.isFinite == true)
    }

    @Test func sleepSpreadNeedsCoverageAndUsesRecordedNightsOnly() {
        let sleep = [-7, -6, -4, -1].map { offset in
            SleepInterval(start: Fixture.day(offset),
                          end: Fixture.day(offset).addingTimeInterval((offset == -1 ? 8 : 6) * 3600), stage: .asleepCore)
        }
        let spread = summary(Fixture.snapshot(sleep: sleep)).sleepSpread
        #expect(spread?.shortest == 6)
        #expect(spread?.longest == 8)
        #expect(spread?.recordedNights == 4)
        #expect(summary(Fixture.snapshot(sleep: Array(sleep.dropLast()))).sleepSpread == nil)
    }

    @Test func midnightStillIncludesTodayAndTwoFullPeriods() {
        let snapshot = SnapshotBuilder.build(raw: .empty, access: .requested,
                                             now: Fixture.day(0), calendar: Fixture.calendar)
        #expect(snapshot.series(.sleep).days.count == 15)
        #expect(InsightEngine.insights(for: snapshot).allSatisfy { $0.recent.lastDay == Fixture.day(-1) })
    }
}
