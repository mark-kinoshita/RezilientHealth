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
