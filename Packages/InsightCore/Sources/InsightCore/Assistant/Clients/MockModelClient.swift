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
        let answer = Self.answer(question: request.question, context: request.context, history: request.history)
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

    static func answer(question: String, context: InsightContext, history: [ConversationTurn] = []) -> InsightAnswer {
        let q = question.lowercased()
        let available = [HealthMetric.sleep, .restingHeartRate, .steps].filter {
            context.metrics[$0.rawValue]?.status != .noData && context.metrics[$0.rawValue] != nil
        }
        let relevant: [HealthMetric]
        if q.contains("changed together") || q.contains("stood out") {
            relevant = available
        } else if q.contains("sleep") {
            relevant = available.filter { $0 == .sleep }
        } else if q.contains("heart") {
            relevant = available.filter { $0 == .restingHeartRate }
        } else if q.contains("activity") || q.contains("step") {
            relevant = available.filter { $0 == .steps }
        } else {
            relevant = available
        }

        if clinicalTerms.contains(where: q.contains) {
            return InsightAnswer(
                status: .needsClinician, displayMetrics: relevant.map(\.rawValue), observations: [],
                generalInfo: ["Wearable trends can't diagnose a condition or guide treatment. A clinician can consider these readings alongside your history."],
                limitations: ["This app doesn't make diagnoses or medication recommendations."]
            )
        }
        if let (_, missing) = untrackedTerms.first(where: { q.contains($0.0) }) {
            return InsightAnswer(
                status: .insufficientData, displayMetrics: [], observations: [], generalInfo: [],
                limitations: ["This app doesn't have \(missing) data. It reads steps, sleep, and resting heart rate."]
            )
        }
        if q.contains("walking habit"), history.last?.answer.generalInfo.contains(where: { $0.contains("walking habit") }) == true {
            return InsightAnswer(
                status: .answered, takeaway: "Let's focus on consistency rather than a personal step target.",
                displayMetrics: available.contains(.steps) ? [HealthMetric.steps.rawValue] : [], observations: [],
                generalInfo: ["For a walking habit, consider a repeatable time or cue that fits your day. This is general guidance, not a target inferred from your readings."],
                limitations: []
            )
        }
        guard relevant.contains(where: { context.metrics[$0.rawValue]?.currentPeriod.sufficient == true }) else {
            return InsightAnswer(
                status: .insufficientData, displayMetrics: relevant.map(\.rawValue), observations: [], generalInfo: [],
                limitations: ["There isn't enough recent data to answer this. Averages need data on at least half the days in the period."]
            )
        }

        let isStepsAdvice = (q.contains("step") || q.contains("activity"))
            && ["should", "enough", "good amount", "more", "goal"].contains(where: q.contains)
        if isStepsAdvice {
            return InsightAnswer(
                status: .answered,
                takeaway: "Your step count alone doesn't tell us whether you need more activity.",
                displayMetrics: [HealthMetric.steps.rawValue], observations: [],
                generalInfo: ["Are you aiming to build a walking habit or return to your usual activity?"],
                limitations: ["This summary doesn't include your activity goals or personal circumstances."]
            )
        }

        let changes = context.dashboardPatterns.changes.filter { relevant.contains($0.metric) }
        let phrases = changes.prefix(2).map { change in
            switch change.metric {
            case .sleep: change.difference < 0 ? "Less sleep" : "More sleep"
            case .steps: change.difference < 0 ? "Lower activity" : "Higher activity"
            case .restingHeartRate: change.difference < 0 ? "Lower resting heart rate" : "Higher resting heart rate"
            }
        }
        let takeaway = phrases.enumerated().map { index, phrase in index == 0 ? phrase : phrase.lowercased() }.joined(separator: ", ")
        let explanation = changes.count > 1
            ? "These changes happened in the same period. Your data can't tell us why."
            : "These averages describe recorded days. Differences in coverage can affect the comparison."
        return InsightAnswer(
            status: .answered,
            takeaway: takeaway.isEmpty ? "Your recent recorded averages." : takeaway + ".",
            displayMetrics: relevant.map(\.rawValue),
            observations: [.init(text: explanation, metrics: relevant.map(\.rawValue))],
            generalInfo: ["Wearable patterns can vary from one period to another."], limitations: []
        )
    }
}
