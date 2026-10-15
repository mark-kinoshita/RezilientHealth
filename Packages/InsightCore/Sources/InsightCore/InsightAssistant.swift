import Foundation

public struct AnsweredQuestion: Sendable, Equatable {
    public let question: String
    public let answer: InsightAnswer
    public let removedStatements: Int
    public let sourceLabel: String
    public let isSimulated: Bool
    /// Exactly what was sent, for the "what the AI saw" disclosure.
    public let contextJSON: String
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

    public var message: String {
        switch self {
        case .timeout: "The assistant took too long to respond."
        case .offline: "You appear to be offline."
        case .serviceUnavailable: "The assistant is unavailable right now."
        case .notConfigured: "The assistant isn't set up in this build."
        case .blocked: "The assistant couldn't answer that question."
        case .unreadableResponse: "The assistant's reply couldn't be checked against your data, so it isn't shown."
        case .noHealthData: "Your health data hasn't loaded yet."
        }
    }

    public var isRetryable: Bool {
        switch self {
        case .timeout, .offline, .serviceUnavailable, .unreadableResponse: true
        case .notConfigured, .blocked, .noHealthData: false
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

    public func ask(_ question: String, context: InsightContext) async -> Result<AnsweredQuestion, AskFailure> {
        let contextJSON = context.jsonString()

        // Possible emergencies never wait on (or depend on) a network model.
        if QuestionTriage.isPossibleEmergency(question) {
            return .success(AnsweredQuestion(
                question: question, answer: QuestionTriage.emergencyAnswer, removedStatements: 0,
                sourceLabel: "Built-in safety message (no AI)", isSimulated: false, contextJSON: contextJSON
            ))
        }

        let request = ModelRequest(
            systemInstruction: InsightPrompt.systemInstruction,
            userMessage: InsightPrompt.userMessage(question: question, context: context),
            context: context,
            question: question,
            timeout: timeout
        )

        let raw: String
        do {
            raw = try await client.complete(request)
        } catch {
            return .failure(AskFailure(error))
        }

        guard let decoded = try? InsightAnswer.decode(raw),
              let checked = try? AnswerValidator.validate(decoded, context: context)
        else {
            return .failure(.unreadableResponse)
        }
        let (validated, removed) = checked

        return .success(AnsweredQuestion(
            question: question, answer: validated, removedStatements: removed,
            sourceLabel: client.sourceLabel, isSimulated: client.isSimulated, contextJSON: contextJSON
        ))
    }
}

public enum QuestionTriage {
    static let emergencyPhrases = [
        "chest pain", "can't breathe", "cannot breathe", "trouble breathing", "fainted", "passed out",
        "heart attack", "stroke", "suicid", "kill myself", "hurt myself", "overdose",
    ]

    public static func isPossibleEmergency(_ question: String) -> Bool {
        let q = question.lowercased().replacingOccurrences(of: "’", with: "'")
        return emergencyPhrases.contains(where: q.contains)
    }

    static let emergencyAnswer = InsightAnswer(
        status: .needsClinician,
        observations: [],
        generalInfo: [
            "If you think you might be having a medical emergency, call 911 or your local emergency number now.",
            "If you're thinking about harming yourself, you can call or text 988 (Suicide & Crisis Lifeline, US).",
        ],
        limitations: ["Wearable data can't tell whether something urgent is happening."]
    )
}
