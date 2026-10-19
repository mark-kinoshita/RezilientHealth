import Foundation
import InsightCore
import Observation

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

/// State for the Ask screen. The failure contract (never lose the question,
/// never show an unchecked answer) is unit tested in InsightPresentationTests.
@MainActor
@Observable
public final class AskViewModel {
    public enum State: Equatable {
        case idle
        case loading(question: String)
        case answered(AnswerState)
        case failed(question: String, message: String, canRetry: Bool)
    }

    /// Suggestions follow the range the member is looking at.
    public var range: TimeRange = .week

    public var suggestions: [String] {
        let period = range == .week ? "this week" : "over \(range.currentLabel)"
        return [
            "What stood out \(period)?",
            "What do you notice about my activity \(period)?",
            "Is my resting heart rate trending up or down?",
            "Do I have sleep apnea?",
            "How many calories did I burn?",
        ]
    }

    public var draft = ""
    public private(set) var state: State = .idle
    public private(set) var assistant: InsightAssistant
    public var context: InsightContext? {
        didSet {
            // Losing readable data also invalidates a pinned conversation snapshot.
            if context == nil { startOver() }
        }
    }
    private var history: [ConversationTurn] = []
    private var conversationContext: InsightContext?
    private var requestID: UUID?
    private var activeRequest: Task<Result<AnsweredQuestion, AskFailure>, Never>?

    public init(assistant: InsightAssistant, context: InsightContext?) {
        self.assistant = assistant
        self.context = context
    }

    public var isLoading: Bool {
        if case .loading = state { true } else { false }
    }

    public var canSubmit: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }

    /// Tells the member where answers come from before they ask.
    public var sourceDescription: String {
        switch assistant.client.execution {
        case .simulated:
            "Simulated answers: no AI is connected. Responses are canned, built from your summary."
        case .onDevice:
            "Answers are generated on this device using your health summary and up to three earlier exchanges. Your questions and data stay on this device."
                + (assistant.client.supportsGeneralGuidance ? "" : " This model provides concise data summaries; choose a cloud model for broader wellness explanations.")
        case .cloud:
            "Answers come from \(assistant.client.sourceLabel), using your health summary and up to three earlier exchanges in this session."
        }
    }

    public var isSimulated: Bool { assistant.client.isSimulated }

    /// A provider change never silently resends a question or shares earlier exchanges.
    public func replaceAssistant(with assistant: InsightAssistant) {
        let savedDraft: String
        if case .loading(let question) = state { savedDraft = question }
        else { savedDraft = draft }
        startOver()
        self.assistant = assistant
        draft = savedDraft
    }

    public func ask(suggestion: String) async {
        draft = suggestion
        await submit()
    }

    public func submit() async {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isLoading else { return }
        guard let context = conversationContext ?? context else {
            fail(question, .noHealthData)
            return
        }
        // The question moves into the conversation while it's in flight; a
        // failure puts it back in the field.
        state = .loading(question: question)
        draft = ""
        let id = UUID()
        requestID = id
        let assistant = assistant
        let priorHistory = history
        let task = Task { await assistant.ask(question, context: context, history: priorHistory) }
        activeRequest = task
        let result = await task.value
        // Cancellation alone is insufficient: a client can finish after cancellation.
        guard requestID == id else { return }
        activeRequest = nil
        requestID = nil
        switch result {
        case .success(let answered):
            // Pin a session to the original measurement snapshot. A dashboard refresh
            // must not silently change the facts underneath a follow-up.
            conversationContext = context
            history.append(ConversationTurn(question: question, answer: answered.answer))
            history = Array(history.suffix(3))
            state = .answered(AnswerState(answered))
        case .failure(let failure):
            fail(question, failure)
        }
    }

    /// Back to the suggestions, for a fresh question.
    public func startOver() {
        requestID = nil
        activeRequest?.cancel()
        activeRequest = nil
        state = .idle
        draft = ""
        history = []
        conversationContext = nil
    }

    public func retry() async {
        guard case .failed(let question, _, true) = state else { return }
        draft = question
        await submit()
    }

    private func fail(_ question: String, _ failure: AskFailure) {
        // The draft keeps the question so the member can retry or edit it.
        state = .failed(
            question: question,
            message: failure.message + " Your question is saved below. Nothing was guessed in its place.",
            canRetry: failure.isRetryable
        )
        draft = question
    }
}
