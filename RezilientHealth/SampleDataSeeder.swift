#if DEBUG
import Foundation
import HealthKit
import InsightPresentation

/// Debug-only: writes deterministic synthetic samples into HealthKit so the
/// real read path can be demonstrated on a simulator. Everything written is
/// tagged with this app as the source and can be removed with `clear()`.
nonisolated struct SampleDataSeeder: SampleDataSeeding {
    enum Scenario: String, CaseIterable, Identifiable {
        /// Two weeks with realistic gaps: 2 days without steps or heart rate,
        /// 2 missing nights, and overlapping watch + phone sleep samples.
        case typical
        /// Only older data (ends 9 days ago), to show stale/insufficient states.
        case sparseAndStale

        var id: String { rawValue }
        var title: String {
            switch self {
            case .typical: "Seed typical 2 weeks (with gaps)"
            case .sparseAndStale: "Seed sparse + stale data"
            }
        }
    }

    let store: HKHealthStore
    var calendar = Calendar.current

    var scenarios: [SampleScenario] {
        Scenario.allCases.map { SampleScenario(id: $0.rawValue, title: $0.title) }
    }

    func seed(_ scenario: SampleScenario) async throws {
        guard let scenario = Scenario(rawValue: scenario.id) else { return }
        try await seed(scenario, now: .now)
    }

    func seed(_ scenario: Scenario, now: Date) async throws {
        try await clear()
        var rng = SeededGenerator(seed: 42)
        var samples: [HKSample] = []
        let today = calendar.startOfDay(for: now)

        for offset in -14...0 {
            let day = calendar.date(byAdding: .day, value: offset, to: today)!
            let recentWeek = offset >= -7
            let include: (steps: Bool, hr: Bool, sleep: Bool) = switch scenario {
            case .typical: (![-5, -4].contains(offset), ![-5, -4].contains(offset), ![-9, -2].contains(offset))
            case .sparseAndStale: (offset <= -9, offset <= -11, [-13, -10].contains(offset))
            }

            if include.steps {
                let target = (recentWeek ? 8_400.0 : 6_600.0) + Double.random(in: -1_500...1_500, using: &rng)
                samples += stepSamples(day: day, total: target, now: now)
            }
            if include.hr, let at = calendar.date(bySettingHour: 7, minute: 30, second: 0, of: day), at < now {
                let bpm = (recentWeek ? 58.0 : 61.0) + Double.random(in: -1.5...1.5, using: &rng)
                samples.append(HKQuantitySample(
                    type: HealthKitDataSource.restingHRType,
                    quantity: HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: bpm.rounded()),
                    start: at, end: at
                ))
            }
            if include.sleep {
                let hours = (recentWeek ? 6.8 : 7.3) + Double.random(in: -0.7...0.7, using: &rng)
                samples += sleepSamples(wakeDay: day, hoursAsleep: hours, overlapSource: offset.isMultiple(of: 3), now: now)
            }
        }
        try await store.save(samples)
    }

    /// Deletes only samples this app wrote.
    func clear() async throws {
        let predicate = HKQuery.predicateForObjects(from: .default())
        for type in [HealthKitDataSource.stepType, HealthKitDataSource.restingHRType, HealthKitDataSource.sleepType] as [HKObjectType] {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                store.deleteObjects(of: type, predicate: predicate) { _, _, error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
        }
    }

    private func stepSamples(day: Date, total: Double, now: Date) -> [HKSample] {
        // Three walking blocks; on today, only blocks that have already happened.
        let blocks: [(hour: Int, share: Double)] = [(8, 0.3), (12, 0.3), (18, 0.4)]
        return blocks.compactMap { block in
            guard let start = calendar.date(bySettingHour: block.hour, minute: 0, second: 0, of: day) else { return nil }
            let end = start.addingTimeInterval(45 * 60)
            guard end <= now else { return nil }
            return HKQuantitySample(
                type: HealthKitDataSource.stepType,
                quantity: HKQuantity(unit: .count(), doubleValue: (total * block.share).rounded()),
                start: start, end: end
            )
        }
    }

    private func sleepSamples(wakeDay: Date, hoursAsleep: Double, overlapSource: Bool, now: Date) -> [HKSample] {
        let bedtime = calendar.date(byAdding: .minute, value: -60, to: wakeDay)! // 23:00 the night before
        let asleepStart = bedtime.addingTimeInterval(15 * 60)
        let wake = asleepStart.addingTimeInterval(hoursAsleep * 3600 + 15 * 60) // includes a 15-min awake block
        let awakeStart = asleepStart.addingTimeInterval(3 * 3600)
        guard wake.addingTimeInterval(10 * 60) <= now else { return [] }

        func sample(_ value: HKCategoryValueSleepAnalysis, _ start: Date, _ end: Date) -> HKCategorySample {
            HKCategorySample(type: HealthKitDataSource.sleepType, value: value.rawValue, start: start, end: end)
        }
        var result: [HKSample] = [
            sample(.inBed, bedtime, wake.addingTimeInterval(10 * 60)),
            sample(.asleepCore, asleepStart, asleepStart.addingTimeInterval(2 * 3600)),
            sample(.asleepDeep, asleepStart.addingTimeInterval(2 * 3600), awakeStart),
            sample(.awake, awakeStart, awakeStart.addingTimeInterval(15 * 60)),
            sample(.asleepREM, awakeStart.addingTimeInterval(15 * 60), awakeStart.addingTimeInterval(105 * 60)),
            sample(.asleepCore, awakeStart.addingTimeInterval(105 * 60), wake),
        ]
        if overlapSource {
            // A second tracker recording the same night. Must not be double-counted.
            result.append(sample(.asleepUnspecified, asleepStart.addingTimeInterval(20 * 60), wake.addingTimeInterval(-30 * 60)))
        }
        return result
    }
}

/// Deterministic RNG so seeded demos look the same every run.
nonisolated struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
#endif
