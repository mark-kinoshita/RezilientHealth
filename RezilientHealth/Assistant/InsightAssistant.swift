import Foundation

public struct AnsweredQuestion: Sendable, Equatable {
    public let question: String
    public let answer: InsightAnswer
    public let removedStatements: Int
    public let sourceLabel: String
    public let isSimulated: Bool
    /// Exactly what was sent, for the "what the AI saw" disclosure.
    public let contextJSON: String
    public let context: InsightContext
    public var history: [ConversationTurn] = []
    public var modelInput: String? = nil
}

public enum AskFailure: Error, Equatable, Sendable {
    case timeout
    case offline
    case serviceUnavailable
    case notConfigured
    case blocked
    /// The model replied, but not in the agreed shape. We never show raw text.
    case unreadableResponse
    case noHealthData
    case modelUnavailable(reason: String)
    case contextLimit

    public var message: String {
        switch self {
        case .timeout: "The assistant took too long to respond."
        case .offline: "You appear to be offline."
        case .serviceUnavailable: "The assistant is unavailable right now."
        case .notConfigured: "The assistant isn't set up in this build."
        case .blocked: "The assistant couldn't answer that question."
        case .unreadableResponse: "The assistant's reply couldn't be checked against your data, so it isn't shown."
        case .noHealthData: "Your health data hasn't loaded yet."
        case .modelUnavailable(let reason): reason
        case .contextLimit: "This model can't fit the current question and context. Start a new question or choose another model."
        }
    }

    public var isRetryable: Bool {
        switch self {
        case .timeout, .offline, .serviceUnavailable, .unreadableResponse: true
        case .notConfigured, .blocked, .noHealthData, .modelUnavailable, .contextLimit: false
        }
    }

    init(_ error: ModelError) {
        switch error {
        case .timeout: self = .timeout
        case .offline: self = .offline
        case .missingAPIKey: self = .notConfigured
        case .blocked: self = .blocked
        case .emptyResponse: self = .unreadableResponse
        case .http, .transport: self = .serviceUnavailable
        case .unavailable(let reason): self = .modelUnavailable(reason: reason)
        case .contextLimit: self = .contextLimit
        }
    }
}

/// Orchestrates one question: local safety check, model call, decode, validate.
public struct InsightAssistant: Sendable {
    public let client: any InsightModelClient
    public let timeout: TimeInterval

    public init(client: any InsightModelClient, timeout: TimeInterval = 20) {
        self.client = client
        self.timeout = timeout
    }

    public func ask(_ question: String, context: InsightContext, history: [ConversationTurn] = []) async -> Result<AnsweredQuestion, AskFailure> {
        let inputContext = client.inputPolicy.prepare(context, question: question)
        let contextJSON = inputContext.jsonString()

        // Possible emergencies never wait on (or depend on) a network model.
        if QuestionTriage.isPossibleEmergency(question) {
            return .success(AnsweredQuestion(
                question: question, answer: QuestionTriage.emergencyAnswer, removedStatements: 0,
                sourceLabel: "Built-in safety message (no AI)", isSimulated: false, contextJSON: contextJSON, context: context
            ))
        }

        let request = ModelRequest(
            systemInstruction: InsightPrompt.instructions(for: client.promptStyle),
            userMessage: InsightPrompt.userMessage(question: question, context: inputContext, history: history),
            context: inputContext,
            question: question,
            timeout: timeout,
            history: Array(history.suffix(3))
        )

        let raw: String
        do {
            raw = try await client.complete(request)
        } catch {
            return .failure(AskFailure(error))
        }

        guard let decoded = try? InsightAnswer.decode(raw),
              let checked = try? AnswerValidator.validate(decoded, context: inputContext)
        else {
            return .failure(.unreadableResponse)
        }
        let (validated, removed) = checked

        return .success(AnsweredQuestion(
            question: question, answer: validated, removedStatements: removed,
            sourceLabel: client.sourceLabel, isSimulated: client.isSimulated, contextJSON: contextJSON, context: context,
            history: Array(history.suffix(3)),
            modelInput: "INSTRUCTIONS:\n\(request.systemInstruction)\n\n\(request.userMessage)"
        ))
    }
}
