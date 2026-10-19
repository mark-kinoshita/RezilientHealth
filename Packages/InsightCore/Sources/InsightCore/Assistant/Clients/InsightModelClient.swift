import Foundation

/// Only validated exchanges from this in-memory session are carried forward.
public struct ConversationTurn: Codable, Sendable, Equatable {
    public let question: String
    public let answer: InsightAnswer

    public init(question: String, answer: InsightAnswer) {
        self.question = question
        self.answer = answer
    }
}

public struct ModelRequest: Sendable {
    public let systemInstruction: String
    public let userMessage: String
    /// The context actually prepared for this provider; the UI retains its full snapshot separately.
    public let context: InsightContext
    public let question: String
    public let timeout: TimeInterval
    public var history: [ConversationTurn] = []
}

public enum ModelError: Error, Equatable, Sendable {
    case missingAPIKey
    case timeout
    case offline
    case http(status: Int, message: String?)
    case blocked(reason: String)
    case emptyResponse
    case transport(String)
    case unavailable(reason: String)
    case contextLimit
}

public enum ModelExecution: Sendable, Equatable {
    case cloud, onDevice, simulated
}

public enum ModelPromptStyle: Sendable, Equatable {
    case standard, compact
}

public enum ModelInputPolicy: Sendable, Equatable {
    case full, summaryOnly

    public func prepare(_ context: InsightContext, question: String = "") -> InsightContext {
        guard self == .summaryOnly else { return context }
        let question = question.lowercased()
        var relevant = Set<HealthMetric>()
        if ["step", "activity", "walk"].contains(where: question.contains) { relevant.insert(.steps) }
        if question.contains("sleep") { relevant.insert(.sleep) }
        if question.contains("resting") && question.contains("heart") { relevant.insert(.restingHeartRate) }
        return context.withoutDailyReadings(keeping: relevant.isEmpty ? nil : relevant)
    }
}

/// One interface for every model backend, real or simulated.
public protocol InsightModelClient: Sendable {
    /// Shown under every answer so the member knows where it came from.
    var sourceLabel: String { get }
    var isSimulated: Bool { get }
    var execution: ModelExecution { get }
    var inputPolicy: ModelInputPolicy { get }
    var promptStyle: ModelPromptStyle { get }
    var supportsGeneralGuidance: Bool { get }
    /// Returns the model's raw JSON text. Decoding and validation happen in
    /// InsightAssistant so every backend gets the same checks.
    func complete(_ request: ModelRequest) async throws(ModelError) -> String
}

public extension InsightModelClient {
    var execution: ModelExecution { isSimulated ? .simulated : .cloud }
    var inputPolicy: ModelInputPolicy { .full }
    var promptStyle: ModelPromptStyle { .standard }
    var supportsGeneralGuidance: Bool { true }
}
