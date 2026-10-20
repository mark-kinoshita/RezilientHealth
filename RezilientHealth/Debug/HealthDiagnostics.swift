#if DEBUG
import Foundation
import HealthKit

/// Debug-only: asks HealthKit directly what this app can see, bypassing the
/// app's own aggregation, so a blank dashboard on a device can be explained.
enum HealthDiagnostics {
    static func report() async -> String {
        let store = HKHealthStore()
        var lines = ["Health data available: \(HKHealthStore.isHealthDataAvailable())"]
        if let bundle = Bundle.main.bundleIdentifier { lines.append("Bundle: \(bundle)") }

        let request = (try? await store.statusForAuthorizationRequest(
            toShare: HealthKitDataSource.shareTypes, read: HealthKitDataSource.readTypes
        )).map { $0 == .unnecessary ? "already asked" : $0 == .shouldRequest ? "should ask" : "unknown" } ?? "error"
        lines.append("Permission sheet: \(request)")

        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
        let types: [(String, HKSampleType)] = [
            ("Steps", HealthKitDataSource.stepType),
            ("Sleep", HealthKitDataSource.sleepType),
            ("Resting HR", HealthKitDataSource.restingHRType),
        ]
        for (name, type) in types {
            lines.append("")
            lines.append(name)
            // Write status is the only status HealthKit reports; read access is hidden.
            lines.append("  write status: \(describe(store.authorizationStatus(for: type)))")
            do {
                let recent = try await HKSampleQueryDescriptor(
                    predicates: [.sample(type: type, predicate: HKQuery.predicateForSamples(withStart: weekAgo, end: .now))],
                    sortDescriptors: [], limit: 500
                ).result(for: store)
                let sources = Set(recent.map(\.sourceRevision.source.name)).sorted()
                lines.append("  samples, last 7 days: \(recent.count)\(recent.count == 500 ? "+" : "")")
                if !sources.isEmpty { lines.append("  sources: \(sources.joined(separator: ", "))") }
                let latest = try await HKSampleQueryDescriptor(
                    predicates: [.sample(type: type)],
                    sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)], limit: 1
                ).result(for: store).first
                lines.append("  newest sample: \(latest.map { $0.endDate.formatted(date: .abbreviated, time: .shortened) } ?? "none")")
            } catch {
                lines.append("  query error: \(error.localizedDescription)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func describe(_ status: HKAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "not determined"
        case .sharingDenied: "denied"
        case .sharingAuthorized: "authorized"
        @unknown default: "unknown"
        }
    }
}
#endif
