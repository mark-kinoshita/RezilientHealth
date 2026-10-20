import Foundation
import FoundationModels

/// SDK-specific generation stays outside the platform-neutral core package.
/// Each call uses the app's explicit, bounded history rather than hidden session memory.
nonisolated struct AppleFoundationModelClient: InsightModelClient {
    var sourceLabel: String { "Apple Foundation Models (on-device summary)" }
    var isSimulated: Bool { false }
    var execution: ModelExecution { .onDevice }
    var inputPolicy: ModelInputPolicy { .summaryOnly }
    var promptStyle: ModelPromptStyle { .compact }
    var supportsGeneralGuidance: Bool { false }

    static var unavailabilityReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: "Apple's on-device model isn't supported on this device."
            case .appleIntelligenceNotEnabled: "Enable Apple Intelligence in Settings to use the on-device model."
            case .modelNotReady: "Apple's on-device model is still downloading or isn't ready yet."
            @unknown default: "Apple's on-device model is unavailable."
            }
        }
    }

    func complete(_ request: ModelRequest) async throws(ModelError) -> String {
        if let reason = Self.unavailabilityReason { throw .unavailable(reason: reason) }
        do {
            return try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask { try await generate(request) }
                group.addTask {
                    try await Task.sleep(for: .seconds(request.timeout))
                    throw ModelError.timeout
                }
                defer { group.cancelAll() }
                guard let reply = try await group.next() else { throw ModelError.emptyResponse }
                return reply
            }
        } catch let error as ModelError {
            throw error
        } catch {
            throw Self.mapError(error)
        }
    }

    private func generate(_ request: ModelRequest) async throws -> String {
        let model = SystemLanguageModel.default
        let maximumResponseTokens = 640
        if #available(iOS 26.4, *) {
            let promptTokens = try await model.tokenCount(for: Prompt(request.userMessage))
            let instructionTokens = try await model.tokenCount(for: Instructions(request.systemInstruction))
            let schemaTokens = try await model.tokenCount(for: OnDeviceAnswer.generationSchema)
            guard promptTokens + instructionTokens + schemaTokens + maximumResponseTokens + 64 < model.contextSize else {
                throw ModelError.contextLimit
            }
        }
        try Task.checkCancellation()
        let session = LanguageModelSession(model: model, instructions: request.systemInstruction)
        let options = GenerationOptions(temperature: 0.2, maximumResponseTokens: maximumResponseTokens)
        let reply = try await session.respond(to: request.userMessage, generating: OnDeviceAnswer.self, options: options)
        let answer = try reply.content.domainAnswer(question: request.question, context: request.context)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return String(decoding: try encoder.encode(answer), as: UTF8.self)
    }

    private static func mapError(_ error: Error) -> ModelError {
        if #available(iOS 27.0, *), let modelError = error as? SystemLanguageModel.Error,
           case .assetsUnavailable = modelError {
            return .unavailable(reason: "Apple's on-device model isn't ready yet.")
        }
        if #available(iOS 27.0, *), let generationError = error as? LanguageModelError {
            switch generationError {
            case .contextSizeExceeded: return .contextLimit
            case .guardrailViolation, .refusal: return .blocked(reason: "On-device model declined the question")
            case .timeout: return .timeout
            default: return .transport("The on-device model couldn't complete this question.")
            }
        }
        if #available(iOS 27.0, *) {
            return .transport("The on-device model couldn't complete this question.")
        } else {
            return mapLegacyError(error)
        }
    }

    @available(iOS, introduced: 26.0, obsoleted: 27.0)
    private static func mapLegacyError(_ error: Error) -> ModelError {
        guard let error = error as? LanguageModelSession.GenerationError else {
            return .transport("The on-device model couldn't complete this question.")
        }
        switch error {
        case .exceededContextWindowSize: return .contextLimit
        case .guardrailViolation, .refusal: return .blocked(reason: "On-device model declined the question")
        case .assetsUnavailable: return .unavailable(reason: "Apple's on-device model isn't ready yet.")
        default: return .transport("The on-device model couldn't complete this question.")
        }
    }
}

/// A deliberately narrow generation surface for a smaller model. Numerical evidence
/// and data notes remain local; unsupported/clinical answers receive local boundary copy.
/// The adapter still returns the shared answer contract for the common validator.
@Generable
private nonisolated struct OnDeviceAnswer: Sendable {
    @Guide(.anyOf(["answered", "insufficient_data", "needs_clinician"]))
    var status: String
    @Guide(description: "Direct answer to the question, at most 160 characters, no numbers, dates, or wellness tips.")
    var takeaway: String
    @Guide(description: "Only metrics relevant to the current question. Activity questions select only steps.", .count(0...3), .element(.anyOf(["steps", "sleep", "resting_heart_rate"])))
    var display_metrics: [String]
    func domainAnswer(question: String, context: InsightContext) throws -> InsightAnswer {
        guard let status = InsightAnswer.Status(rawValue: status) else { throw ModelError.emptyResponse }
        let question = question.lowercased()
        let missing = context.notTrackedInThisApp.first { key in
            question.contains(key.replacingOccurrences(of: "_", with: " "))
                || (key == "calories" && question.contains("calorie"))
                || (key == "heart_rate_variability" && question.contains("hrv"))
        }
        let limitations: [String] = switch status {
        case .answered: []
        case .needsClinician: ["This assistant can't diagnose conditions or advise on medication or treatment decisions."]
        case .insufficientData:
            missing.map { ["This app doesn't track \($0.replacingOccurrences(of: "_", with: " "))."] }
                ?? ["This question needs measurements or context beyond the available summary."]
        }
        return InsightAnswer(
            status: status, takeaway: takeaway, displayMetrics: status == .answered ? display_metrics : [],
            observations: [], generalInfo: [], limitations: limitations
        )
    }
}
