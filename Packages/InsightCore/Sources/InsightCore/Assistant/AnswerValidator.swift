import Foundation

public enum AnswerValidator {
    public enum Rejection: Error, Equatable {
        case empty
    }

    /// Enforces the line between "your data shows" and general information:
    /// a data observation must cite at least one metric that actually has data
    /// in the context. Anything else is dropped and the drop is disclosed.
    public static func validate(_ answer: InsightAnswer, context: InsightContext) throws(Rejection) -> (InsightAnswer, removed: Int) {
        let available = Set(context.metricsWithData.map(\.rawValue))
        let kept = answer.observations.filter { observation in
            !observation.metrics.isEmpty
                && observation.metrics.allSatisfy(available.contains)
                && !observation.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let removed = answer.observations.count - kept.count
        var limitations = answer.limitations
        if removed > 0 {
            limitations.append("\(removed) statement\(removed == 1 ? " was" : "s were") hidden because \(removed == 1 ? "it wasn't" : "they weren't") backed by data in this app.")
        }
        let cleaned = InsightAnswer(
            status: answer.status,
            observations: kept,
            generalInfo: answer.generalInfo.filter { !$0.isEmpty },
            limitations: limitations
        )
        if cleaned.observations.isEmpty && cleaned.generalInfo.isEmpty && answer.limitations.isEmpty {
            throw .empty
        }
        return (cleaned, removed)
    }
}
