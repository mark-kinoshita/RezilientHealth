import Foundation

/// Display-ready version of a validated answer.
public struct AnswerState: Sendable, Equatable {
    public enum Banner: Sendable, Equatable { case needsClinician, insufficientData }

    public struct Observation: Sendable, Equatable, Identifiable {
        public let id: Int
        public let text: String
        public let metrics: [HealthMetric]
    }

    public let question: String
    public let takeaway: String
    public let metricRows: [AnswerMetricRow]
    public let periodLabel: String?
    public let dataNotes: [String]
    public let followUps: [AnswerFollowUp]
    public let banner: Banner?
    public let observations: [Observation]
    public let generalInfo: [String]
    public let limitations: [String]
    public let contextJSON: String
    public let priorExchangeCount: Int
    public let modelInput: String
    public let footer: String
    /// From the answer itself, so switching backends never relabels an
    /// answer that's already on screen.
    public let isSimulated: Bool

    init(_ answered: AnsweredQuestion) {
        let answer = answered.answer
        question = answered.question
        takeaway = answer.takeaway
        let rows = AnswerMetricPresenter.rows(keys: answer.displayMetrics, context: answered.context)
        metricRows = rows
        periodLabel = rows.first.map { row in
            row.previousRange.map { "\(row.currentRange) compared with \($0)" } ?? row.currentRange
        }
        var notes = rows.flatMap(\.notes) + answer.limitations
        if !answered.history.isEmpty {
            notes.append("This follow-up uses the same health snapshot and up to three earlier exchanges. Start a new question to use refreshed data.")
        }
        if rows.contains(where: { row in
            answered.context.metrics[row.metric.rawValue]?.daily.contains { $0.date == answered.context.window.end && $0.value != nil } == true
        }) {
            notes.append("Today's values are shown separately and excluded from these comparisons.")
        }
        var seen = Set<String>()
        dataNotes = notes.filter { seen.insert($0).inserted }
        followUps = answer.status == .answered ? [HealthMetric.sleep, .steps, .restingHeartRate].filter { metric in
            rows.contains { $0.metric == metric && $0.canExplore }
        }.prefix(2).map { metric in
            let title: String = switch metric {
            case .sleep: "Explore my sleep"
            case .steps: "Show my activity"
            case .restingHeartRate: "Explore heart rate"
            }
            return AnswerFollowUp(metric: metric, title: title,
                                  question: "What do you notice about my \(metric.displayName.lowercased()) over the last \(answered.context.window.periodDays) days?")
        } : []
        banner = switch answer.status {
        case .answered: nil
        case .needsClinician: .needsClinician
        case .insufficientData: .insufficientData
        }
        observations = answer.observations.enumerated().map { index, observation in
            Observation(id: index, text: observation.text, metrics: observation.metrics.compactMap(HealthMetric.init(rawValue:)))
        }
        var seenGuidance = Set<String>()
        generalInfo = answer.generalInfo.filter { seenGuidance.insert($0).inserted }
        limitations = answer.limitations
        contextJSON = answered.contextJSON
        priorExchangeCount = answered.history.count
        modelInput = answered.modelInput ?? ("INSTRUCTIONS:\n\(InsightPrompt.systemInstruction)\n\n" + InsightPrompt.userMessage(
            question: answered.question, context: answered.context, history: answered.history
        ))
        footer = "\(answered.sourceLabel). Not medical advice."
        isSimulated = answered.isSimulated
    }
}
