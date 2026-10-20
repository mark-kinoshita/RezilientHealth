@testable import RezilientHealth
import Foundation
import Testing

/// Protects the fallback used when HealthKit statistics don't cover a day.
@Suite struct DailyQuantityAggregatorTests {
    @Test func phoneAndWatchCountingTheSameWalkAreNotAddedTogether() {
        let morning = Fixture.day(-40) + 9 * 3600
        let samples = [
            QuantitySampleRecord(start: morning, value: 3_000, sourceID: "watch"),
            QuantitySampleRecord(start: morning + 3600, value: 2_000, sourceID: "watch"),
            QuantitySampleRecord(start: morning, value: 4_500, sourceID: "phone"),
        ]
        let days = DailyQuantityAggregator.cumulativeByDay(samples, calendar: Fixture.calendar)
        #expect(days[Fixture.day(-40)] == 5_000)   // max source total, not 9,500
    }

    @Test func statisticsWinAndSamplesOnlyFillUncoveredDays() {
        let merged = DailyQuantityAggregator.merge(
            statistics: [Fixture.day(-1): 8_000],
            fallback: [Fixture.day(-1): 99, Fixture.day(-40): 5_000]
        )
        #expect(merged == [Fixture.day(-1): 8_000, Fixture.day(-40): 5_000])
        #expect(merged[Fixture.day(-41)] == nil)   // still no data, not zero
    }

    @Test func restingHeartRateAveragesTheDaysSamples() {
        let day = Fixture.day(-50) + 7 * 3600
        let days = DailyQuantityAggregator.averageByDay(
            [.init(start: day, value: 60, sourceID: "watch"), .init(start: day + 60, value: 58, sourceID: "watch")],
            calendar: Fixture.calendar
        )
        #expect(days[Fixture.day(-50)] == 59)
    }
}
