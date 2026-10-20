#if DEBUG
import Foundation
import HealthKit

/// Debug-only: writes deterministic synthetic samples into HealthKit so the
/// real read path can be demonstrated on a simulator. Everything written is
/// tagged with this app as the source and can be removed with `clear()`.
nonisolated struct SampleDataSeeder: SampleDataSeeding {
    enum Scenario: String, CaseIterable, Identifiable {
        /// The demo: six steady months, then a rough last week (less sleep,
        /// higher resting HR, fewer steps, one missed night) seeded through
        /// this morning, so every card shows a real change and nothing is stale.
        case story
        /// Six months (enough to compare 3 months with the 3 before) with
        /// realistic gaps: a week the watch wasn't worn, scattered missing
        /// days and nights, overlapping watch + phone sleep samples, and a
        /// gradual trend (more steps, lower resting HR, slightly less sleep).
        case typical
        /// Only older data (ends 9 days ago), to show stale/insufficient states.
        case sparseAndStale

        var id: String { rawValue }
        var title: String {
            switch self {
            case .story: "Seed demo story (rough last week)"
            case .typical: "Seed typical 6 months (with gaps)"
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

        let firstOffset = scenario == .sparseAndStale ? -14 : -180
        for offset in firstOffset...0 {
            let day = calendar.date(byAdding: .day, value: offset, to: today)!
            // 0 at the oldest day, 1 at today: drives a gradual trend.
            let progress = Double(offset - firstOffset) / Double(-firstOffset)
            let weekend = calendar.isDateInWeekend(day)
            let include: (steps: Bool, hr: Bool, sleep: Bool)
            switch scenario {
            case .typical:
                let watchOff = (-52 ... -46).contains(offset)          // a week the watch stayed in a drawer
                let missedDay = [-5, -4, -23, -61, -97, -130].contains(offset)
                let missedNight = [-2, -9, -33, -74, -118].contains(offset)
                include = (!watchOff && !missedDay, !watchOff && !missedDay, !watchOff && !missedNight)
            case .story:
                let watchOff = (-52 ... -46).contains(offset)
                let missedDay = [-23, -61, -97, -130].contains(offset)
                let missedNight = [-3, -33, -74, -118].contains(offset)    // -3: one gap inside the rough week
                include = (!watchOff && !missedDay, !watchOff && !missedDay, !watchOff && !missedNight)
            case .sparseAndStale:
                include = (offset <= -9, offset <= -11, [-13, -10].contains(offset))
            }
            let level = levels(scenario, offset: offset, progress: progress)
            // Quieter noise in the last two weeks so the week-over-week change reads clearly.
            let noise = scenario == .story && offset >= -14 ? 0.4 : 1.0

            if include.steps {
                let base = level.steps + (weekend ? -900 : 0)
                samples += stepSamples(day: day, total: base + noise * Double.random(in: -1_400...1_400, using: &rng), now: now)
            }
            if include.hr, let at = calendar.date(bySettingHour: 7, minute: 30, second: 0, of: day), at < now {
                let bpm = level.bpm + noise * Double.random(in: -1.5...1.5, using: &rng)
                samples.append(HKQuantitySample(
                    type: HealthKitDataSource.restingHRType,
                    quantity: HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: bpm.rounded()),
                    start: at, end: at
                ))
            }
            if include.sleep {
                let hours = level.sleep + (weekend ? 0.4 : 0) + noise * Double.random(in: -0.6...0.6, using: &rng)
                samples += sleepSamples(wakeDay: day, hoursAsleep: hours, overlapSource: offset.isMultiple(of: 3), now: now)
            }
        }
        try await store.save(samples)
    }

    /// Typical daily steps, resting bpm, and hours asleep before noise.
    private func levels(_ scenario: Scenario, offset: Int, progress: Double) -> (steps: Double, bpm: Double, sleep: Double) {
        switch scenario {
        case .story:
            // The rough week covers the last 7 days and today, so it fills the
            // current period whether or not today's sleep is averaged.
            offset >= -7 ? (6_500, 62, 6.45) : (8_200, 58, 7.3)
        case .typical, .sparseAndStale:
            (6_000 + 2_600 * progress, 62 - 4 * progress, 7.4 - 0.5 * progress)
        }
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
