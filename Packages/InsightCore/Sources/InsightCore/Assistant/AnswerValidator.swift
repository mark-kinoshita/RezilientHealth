import Foundation

public enum AnswerValidator {
    public enum Rejection: Error, Equatable {
        case empty
        case invalidNarrative
    }

    /// Enforces the line between "your data shows" and general information:
    /// a data observation must cite at least one metric that actually has data
    /// in the context. Anything else is dropped and the drop is disclosed.
    public static func validate(_ answer: InsightAnswer, context: InsightContext) throws(Rejection) -> (InsightAnswer, removed: Int) {
        let takeaway = answer.takeaway.trimmingCharacters(in: .whitespacesAndNewlines)
        // The model explains patterns, never supplies the numerical UI. Reject
        // accidental numerical prose rather than showing conflicting figures.
        guard !takeaway.isEmpty, takeaway.count <= 160,
              takeaway.rangeOfCharacter(from: .decimalDigits) == nil,
              answer.observations.count <= 4,
              answer.observations.allSatisfy({ $0.text.count <= 300 && $0.text.rangeOfCharacter(from: .decimalDigits) == nil })
        else { throw .invalidNarrative }

        let available = Set(context.metricsWithData.map(\.rawValue))
        var seen = Set<String>()
        let selected = answer.displayMetrics.filter { available.contains($0) && seen.insert($0).inserted }
        let missingSelections = Set(answer.displayMetrics).subtracting(available)
        let kept = answer.observations.filter { observation in
            !observation.metrics.isEmpty
                && observation.metrics.allSatisfy(available.contains)
                && !observation.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let removed = answer.observations.count - kept.count
        var limitations = answer.limitations
        if !missingSelections.isEmpty {
            limitations.append("Some requested metric cards were omitted because this app has no recorded data for them.")
        }
        if removed > 0 {
            limitations.append("\(removed) statement\(removed == 1 ? " was" : "s were") hidden because \(removed == 1 ? "it wasn't" : "they weren't") backed by data in this app.")
        }
        let status: InsightAnswer.Status = answer.status == .answered && !selected.isEmpty
            && selected.allSatisfy { context.metrics[$0]?.currentPeriod.sufficient != true }
            ? .insufficientData : answer.status
        let cleaned = InsightAnswer(
            status: status,
            takeaway: removed > 0 || !missingSelections.isEmpty || status != .answered
                ? InsightAnswer.fallbackTakeaway(for: status) : takeaway,
            displayMetrics: selected,
            observations: kept,
            generalInfo: answer.generalInfo.filter { !$0.isEmpty },
            limitations: limitations
        )
        if selected.isEmpty && cleaned.observations.isEmpty && cleaned.generalInfo.isEmpty && answer.limitations.isEmpty {
            throw .empty
        }
        return (cleaned, removed)
    }
}
