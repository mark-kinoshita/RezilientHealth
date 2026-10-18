import Foundation

/// Clearly-labeled stand-in used when no API key is configured, in tests, and
/// to reproduce failures on demand. It applies the same rules as the prompt
/// using simple keyword checks, which is good enough to demo boundary behavior
/// but is not how real answers are produced.
public struct MockModelClient: InsightModelClient {
    public enum Behavior: String, CaseIterable, Sendable, Identifiable {
        case normal, timeout, serverError, malformed
        public var id: String { rawValue }
    }

    public let behavior: Behavior
    let delay: Duration

    public init(behavior: Behavior = .normal, delay: Duration = .milliseconds(600)) {
        self.behavior = behavior
        self.delay = delay
    }

    public var sourceLabel: String { "Simulated response (mock, no AI)" }
    public var isSimulated: Bool { true }

    public func complete(_ request: ModelRequest) async throws(ModelError) -> String {
        try? await Task.sleep(for: delay)
        switch behavior {
        case .timeout: throw .timeout
        case .serverError: throw .http(status: 503, message: "Simulated outage")
        case .malformed: return "Sure! Your steps look great this week."
        case .normal: break
        }
        let answer = Self.answer(question: request.question, context: request.context)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return String(decoding: (try? encoder.encode(answer)) ?? Data(), as: UTF8.self)
    }

    static let clinicalTerms = ["diagnos", "disease", "disorder", "apnea", "afib", "arrhythmia", "medication", "medicine", "dose", "prescri", "treat", "should i take", "is something wrong", "am i sick"]
    static let untrackedTerms: [(String, String)] = [
        ("hrv", "heart rate variability"), ("variability", "heart rate variability"),
        ("calorie", "calories"), ("blood pressure", "blood pressure"), ("glucose", "blood glucose"),
        ("weight", "weight"), ("stress", "stress"), ("diet", "nutrition"), ("food", "nutrition"),
        ("workout", "workouts"), ("running", "workouts"), ("period", "menstrual cycle"),
    ]

    static func answer(question: String, context: InsightContext) -> InsightAnswer {
        let q = question.lowercased()
        let observations = HealthMetric.allCases.compactMap { metric -> InsightAnswer.Observation? in
            guard let m = context.metrics[metric.rawValue], m.currentPeriod.sufficient, let avg = m.currentPeriod.average else { return nil }
            var text = "Over \(m.currentPeriod.start ?? "?") to \(m.currentPeriod.end ?? "?"), your \(metric.displayName.lowercased()) averaged \(formatted(avg, metric)) on \(m.currentPeriod.daysWithData) of \(m.currentPeriod.daysInPeriod) days with data"
            if m.previousPeriod.sufficient, let prior = m.previousPeriod.average {
                text += ", compared with \(formatted(prior, metric)) in the period before"
            }
            return .init(text: text + ".", metrics: [metric.rawValue])
        }
        let gaps = context.metrics.compactMap { key, m -> String? in
            let missing = m.currentPeriod.daysInPeriod - m.currentPeriod.daysWithData
            return missing > 0 ? "\(HealthMetric(rawValue: key)?.displayName ?? key): \(missing) of the last \(m.currentPeriod.daysInPeriod) days have no data, so they're left out." : nil
        }.sorted()

        if clinicalTerms.contains(where: q.contains) {
            return InsightAnswer(
                status: .needsClinician,
                observations: Array(observations.prefix(2)),
                generalInfo: ["Wearable trends can't diagnose a condition or guide treatment. A clinician can look at these numbers alongside your history."],
                limitations: ["This app doesn't make diagnoses or medication recommendations."] + gaps
            )
        }
        if let (_, missing) = untrackedTerms.first(where: { q.contains($0.0) }) {
            return InsightAnswer(
                status: .insufficientData,
                observations: [],
                generalInfo: [],
                limitations: ["This app doesn't have \(missing) data, so it can't answer that from your data. It currently reads steps, sleep, and resting heart rate."]
            )
        }
        if observations.isEmpty {
            return InsightAnswer(
                status: .insufficientData, observations: [], generalInfo: [],
                limitations: ["There isn't enough recent data to answer that. Averages need data on at least half the days in the period."] + gaps
            )
        }
        return InsightAnswer(
            status: .answered,
            observations: observations,
            generalInfo: ["Many adults aim for 7 or more hours of sleep, and regular daily movement supports heart health."],
            limitations: gaps
        )
    }

    private static func formatted(_ value: Double, _ metric: HealthMetric) -> String {
        switch metric {
        case .steps: "\(Int(value.rounded()).formatted()) steps"
        case .sleep: Formatting.hours(value)
        case .restingHeartRate: "\(Int(value.rounded())) bpm"
        }
    }
}
