import Foundation

/// Structured reply the model must return (enforced by a JSON schema on the
/// request and re-checked here).
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
    public let observations: [Observation]
    public let generalInfo: [String]
    public let limitations: [String]

    public init(status: Status, observations: [Observation], generalInfo: [String], limitations: [String]) {
        self.status = status
        self.observations = observations
        self.generalInfo = generalInfo
        self.limitations = limitations
    }

    public static func decode(_ json: String) throws -> InsightAnswer {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(InsightAnswer.self, from: Data(json.utf8))
    }
}
