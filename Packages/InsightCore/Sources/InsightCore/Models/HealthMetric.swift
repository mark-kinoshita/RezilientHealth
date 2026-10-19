import Foundation

/// The metrics this prototype reads. Anything else is explicitly "not tracked"
/// so the model can say so instead of guessing.
public enum HealthMetric: String, CaseIterable, Codable, Sendable, Identifiable {
    case steps
    case sleep
    case restingHeartRate = "resting_heart_rate"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .steps: "Steps"
        case .sleep: "Sleep"
        case .restingHeartRate: "Resting heart rate"
        }
    }

    public var unit: String {
        switch self {
        case .steps: "steps"
        case .sleep: "hours asleep"
        case .restingHeartRate: "bpm"
        }
    }

    /// Whether today's value is final. Steps and resting HR accumulate through
    /// the day; "today's" sleep is last night, which has already ended.
    public var todayIsComplete: Bool { self == .sleep }
}

/// The active metric set is deliberately separate from the metric cases.
/// Product can hide or swap supported metrics here without changing dashboard
/// iteration, insight generation, or the model response schema.
public enum MetricCatalog {
    public static let enabled: [HealthMetric] = [.steps, .sleep, .restingHeartRate]
}
