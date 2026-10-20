import Foundation
import Observation

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
