import Foundation

/// Build-time configuration injected through Config/*.xcconfig → Info.plist.
enum AppConfiguration {
    static var geminiAPIKey: String? {
        let value = (Bundle.main.object(forInfoDictionaryKey: "GeminiAPIKey") as? String)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        let placeholders: Set<String> = ["", "$(GEMINI_API_KEY)", "your-key-here"]
        return placeholders.contains(value) ? nil : value
    }

    static var geminiModel: String {
        let value = Bundle.main.object(forInfoDictionaryKey: "GeminiModel") as? String ?? ""
        return value.isEmpty || value.hasPrefix("$(") ? "gemini-flash-latest" : value
    }

    static var assistantID: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "AssistantProvider") as? String ?? ""
        return value.isEmpty || value.hasPrefix("$(") ? nil : value
    }

    static var alternateGeminiModels: [String] {
        let value = Bundle.main.object(forInfoDictionaryKey: "GeminiAlternateModels") as? String ?? ""
        guard !value.hasPrefix("$(") else { return [] }
        return value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static var geminiThinkingBudget: Int? {
        let value = Bundle.main.object(forInfoDictionaryKey: "GeminiThinkingBudget") as? String ?? "0"
        return Int(value.trimmingCharacters(in: .whitespaces))
    }
}

/// Model backends offered to the dashboard view model. Simulated modes
/// reproduce boundary and failure behavior on demand.
enum AssistantCatalog {
    static let geminiID = "gemini"
    static let appleID = "apple"

    static var defaultID: String {
        if let configured = AppConfiguration.assistantID {
            return options.contains { $0.id == configured } ? configured : "mock"
        }
        return AppConfiguration.geminiAPIKey == nil ? "mock" : geminiID
    }

    static var options: [AssistantOption] {
        let key = AppConfiguration.geminiAPIKey
        let model = AppConfiguration.geminiModel
        let thinkingBudget = AppConfiguration.geminiThinkingBudget
        var seen = Set<String>()
        let models = ([model] + AppConfiguration.alternateGeminiModels).filter { seen.insert($0).inserted }
        let cloudOptions = models.map { selectedModel in
            AssistantOption(id: selectedModel == model ? geminiID : "gemini:\(selectedModel)",
                            title: "Gemini (\(selectedModel))",
                            unavailableReason: { key == nil ? "Configure a Gemini API key to use this model." : nil }) {
                GeminiClient(apiKey: key ?? "", model: selectedModel,
                             thinkingBudget: selectedModel == model ? thinkingBudget : nil)
            }
        }
        return cloudOptions + [
            AssistantOption(id: appleID, title: "Apple · on-device summaries",
                            unavailableReason: { AppleFoundationModelClient.unavailabilityReason }) {
                AppleFoundationModelClient()
            },
            AssistantOption(id: "mock", title: "Simulated: normal") { MockModelClient(behavior: .normal) },
            AssistantOption(id: "mockTimeout", title: "Simulated: timeout", isDiagnostic: true) { MockModelClient(behavior: .timeout, delay: .seconds(2)) },
            AssistantOption(id: "mockServerError", title: "Simulated: service error", isDiagnostic: true) { MockModelClient(behavior: .serverError) },
            AssistantOption(id: "mockMalformed", title: "Simulated: malformed reply", isDiagnostic: true) { MockModelClient(behavior: .malformed) },
        ]
    }
}
