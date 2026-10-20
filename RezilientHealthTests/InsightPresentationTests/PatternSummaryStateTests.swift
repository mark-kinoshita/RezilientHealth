@testable import RezilientHealth
import Foundation
import Testing

@Suite struct PatternSummaryStateTests {
    private func state(_ snapshot: HealthSnapshot) -> PatternSummaryState {
        .build(snapshot: snapshot, insights: InsightEngine.insights(for: snapshot))
    }

    @Test func relatedChangesLeadWithEvidenceAndAnExplorationQuestion() {
        let steps = Dictionary(uniqueKeysWithValues: (-14 ... -1).map { ($0, $0 < -7 ? 8000.0 : 5000.0) })
        let sleep = (-14 ... -1).map { offset in
            SleepInterval(start: Fixture.day(offset), end: Fixture.day(offset).addingTimeInterval((offset < -7 ? 8 : 6) * 3600), stage: .asleepCore)
        }
        let result = state(Fixture.snapshot(steps: steps, sleep: sleep))
        #expect(result.title == "Sleep dipped. Activity dipped.")
        #expect(result.explanation == "Compared with the previous week.")
        #expect(result.evidence.count == 2)
        #expect(result.evidence.first { $0.metric == .steps }?.text.contains("3,000 fewer") == true)
        #expect(result.evidence.allSatisfy { $0.coverage.contains("7/7 current") })
        #expect(result.question.contains("What changed together"))
    }

    @Test func emptyAndStableStatesDoNotInventAChange() {
        let empty = state(Fixture.snapshot())
        #expect(empty.title == "Not enough data for a comparison yet.")
        #expect(empty.evidence.isEmpty)
        let steps = Dictionary(uniqueKeysWithValues: (-14 ... -1).map { ($0, 8000.0) })
        let stable = state(Fixture.snapshot(steps: steps))
        #expect(stable.title == "No large shifts in comparable data.")
        #expect(stable.explanation.contains("1 of 3 metrics"))
        #expect(stable.evidence.isEmpty)
    }

    @Test func summaryDeltaAndAccessibleDescriptionMatchRoundedEndpoints() {
        let heartRate = Dictionary(uniqueKeysWithValues: (-14 ... -1).map { ($0, $0 < -7 ? 58.4 : 62.6) })
        let result = state(Fixture.snapshot(restingHR: heartRate))
        #expect(result.evidence.first?.previousValue == "58")
        #expect(result.evidence.first?.currentValue == "63")
        #expect(result.evidence.first?.changeText == "+5 bpm")
        #expect(result.evidence.first?.text.contains("5 bpm higher") == true)
    }
}
