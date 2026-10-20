@testable import RezilientHealth
import Foundation

enum Fixture {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    /// Thursday Oct 15 2026, 2pm local.
    static let now = date(2026, 10, 15, 14)

    static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    /// Start of day `offset` days from today (0 = today, -1 = yesterday).
    static func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
    }

    static func snapshot(
        steps: [Int: Double] = [:],
        restingHR: [Int: Double] = [:],
        sleep: [SleepInterval] = [],
        latest: [HealthMetric: Date]? = nil,
        access: HealthAccessState = .requested
    ) -> HealthSnapshot {
        let raw = RawHealthData(
            dailySteps: Dictionary(uniqueKeysWithValues: steps.map { (day($0.key), $0.value) }),
            sleepIntervals: sleep,
            dailyRestingHeartRate: Dictionary(uniqueKeysWithValues: restingHR.map { (day($0.key), $0.value) }),
            latestSampleDate: latest ?? [
                .steps: steps.isEmpty ? nil : now,
                .restingHeartRate: restingHR.isEmpty ? nil : now,
                .sleep: sleep.isEmpty ? nil : sleep.map(\.end).max(),
            ].compactMapValues { $0 }
        )
        return SnapshotBuilder.build(raw: raw, access: access, now: now, calendar: calendar)
    }

    static func context(for snapshot: HealthSnapshot) -> InsightContext {
        InsightContextBuilder.build(snapshot: snapshot, insights: InsightEngine.insights(for: snapshot))
    }

    /// Steps on every completed day, so all metrics but steps have no data.
    static var stepsOnlyContext: InsightContext {
        context(for: snapshot(steps: Dictionary(uniqueKeysWithValues: (-14...0).map { ($0, 8000.0) })))
    }
}

/// Records calls and returns a scripted result.
final class ScriptedClient: InsightModelClient, @unchecked Sendable {
    var results: [Result<String, ModelError>]
    private(set) var calls: [ModelRequest] = []

    init(_ results: Result<String, ModelError>...) { self.results = results }

    var sourceLabel: String { "Scripted" }
    var isSimulated: Bool { true }

    func complete(_ request: ModelRequest) async throws(ModelError) -> String {
        calls.append(request)
        return try results.removeFirst().get()
    }
}
