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
    public let banner: Banner?
    public let observations: [Observation]
    public let generalInfo: [String]
    public let limitations: [String]
    public let contextJSON: String
    public let footer: String
    /// From the answer itself, so switching backends never relabels an
    /// answer that's already on screen.
    public let isSimulated: Bool

    init(_ answered: AnsweredQuestion) {
        let answer = answered.answer
        question = answered.question
        banner = switch answer.status {
        case .answered: nil
        case .needsClinician: .needsClinician
        case .insufficientData: .insufficientData
        }
        observations = answer.observations.enumerated().map { index, observation in
            Observation(id: index, text: observation.text, metrics: observation.metrics.compactMap(HealthMetric.init(rawValue:)))
        }
        generalInfo = answer.generalInfo
        limitations = answer.limitations
        contextJSON = answered.contextJSON
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
            "What do you notice about my activity \(period)?",
            "How has my sleep changed?",
            "Is my resting heart rate trending up or down?",
            "Do I have sleep apnea?",
            "How many calories did I burn?",
        ]
    }

    public var introTitle: String { "Ask about your health data" }

    public var introSubtitle: String {
        "Answers use only your steps, sleep, and resting heart rate from \(range.currentLabel), the same numbers as your dashboard."
    }

    public var draft = ""
    public private(set) var state: State = .idle
    public var assistant: InsightAssistant
    public var context: InsightContext?

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
        assistant.client.isSimulated
            ? "Simulated answers: no AI is connected. Responses are canned, built from your summary."
            : "Answers come from \(assistant.client.sourceLabel), using only the summary shown on the dashboard."
    }

    public var isSimulated: Bool { assistant.client.isSimulated }

    public func ask(suggestion: String) async {
        draft = suggestion
        await submit()
    }

    public func submit() async {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isLoading else { return }
        guard let context else {
            fail(question, .noHealthData)
            return
        }
        // The question moves into the conversation while it's in flight; a
        // failure puts it back in the field.
        state = .loading(question: question)
        draft = ""
        switch await assistant.ask(question, context: context) {
        case .success(let answered):
            state = .answered(AnswerState(answered))
        case .failure(let failure):
            fail(question, failure)
        }
    }

    /// Back to the suggestions, for a fresh question.
    public func startOver() {
        guard !isLoading else { return }
        state = .idle
        draft = ""
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
