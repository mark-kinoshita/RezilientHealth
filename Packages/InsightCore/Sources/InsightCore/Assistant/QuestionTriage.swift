import Foundation

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
