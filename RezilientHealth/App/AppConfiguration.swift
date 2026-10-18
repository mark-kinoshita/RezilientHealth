import Foundation
import InsightCore
import InsightPresentation

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
}

/// Model backends offered to the dashboard view model. Simulated modes
/// reproduce boundary and failure behavior on demand.
enum AssistantCatalog {
    static let geminiID = "gemini"

    static var defaultID: String { AppConfiguration.geminiAPIKey == nil ? "mock" : geminiID }

    static var options: [AssistantOption] {
        let key = AppConfiguration.geminiAPIKey
        let model = AppConfiguration.geminiModel
        return [
            AssistantOption(id: geminiID, title: key == nil ? "Gemini (no key configured)" : "Gemini") {
                GeminiClient(apiKey: key ?? "", model: model)
            },
            AssistantOption(id: "mock", title: "Simulated: normal") { MockModelClient(behavior: .normal) },
            AssistantOption(id: "mockTimeout", title: "Simulated: timeout") { MockModelClient(behavior: .timeout, delay: .seconds(2)) },
            AssistantOption(id: "mockServerError", title: "Simulated: service error") { MockModelClient(behavior: .serverError) },
            AssistantOption(id: "mockMalformed", title: "Simulated: malformed reply") { MockModelClient(behavior: .malformed) },
        ]
    }
}
