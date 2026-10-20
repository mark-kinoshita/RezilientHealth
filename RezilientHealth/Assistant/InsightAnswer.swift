import Foundation

/// Normalized reply produced by every provider adapter. Providers use their own
/// structured-generation APIs; the shared assistant decodes and validates this contract.
public struct InsightAnswer: Codable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable {
        /// Answered from the member's data.
        case answered
        /// The question needs data this app doesn't have or that is too sparse.
        case insufficientData = "insufficient_data"
        /// Asks for diagnosis, treatment, or medication decisions.
        case needsClinician = "needs_clinician"
    }

    public struct Observation: Codable, Sendable, Equatable {
        public let text: String
        /// Metric keys from the context this statement relies on.
        public let metrics: [String]

        public init(text: String, metrics: [String]) {
            self.text = text
            self.metrics = metrics
        }
    }

    public let status: Status
    /// A brief, number-free answer to the member's question. Numerical values render from context.
    public let takeaway: String
    public let displayMetrics: [String]
    public let observations: [Observation]
    public let generalInfo: [String]
    public let limitations: [String]

    public init(status: Status, takeaway: String? = nil, displayMetrics: [String]? = nil,
                observations: [Observation], generalInfo: [String], limitations: [String]) {
        self.status = status
        self.takeaway = takeaway ?? Self.fallbackTakeaway(for: status)
        var seen = Set<String>()
        self.displayMetrics = displayMetrics ?? observations.flatMap(\.metrics).filter { seen.insert($0).inserted }
        self.observations = observations
        self.generalInfo = generalInfo
        self.limitations = limitations
    }

    public static func fallbackTakeaway(for status: Status) -> String {
        switch status {
        case .answered: "Here's what your recorded data shows."
        case .insufficientData: "Your data can't fully answer this."
        case .needsClinician: "This is a question for a clinician."
        }
    }

    public static func decode(_ json: String) throws -> InsightAnswer {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(InsightAnswer.self, from: Data(json.utf8))
    }
}
