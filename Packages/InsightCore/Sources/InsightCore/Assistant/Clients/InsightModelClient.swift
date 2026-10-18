import Foundation

public struct ModelRequest: Sendable {
    public let systemInstruction: String
    public let userMessage: String
    /// Passed through so the deterministic mock can answer from the same data.
    public let context: InsightContext
    public let question: String
    public let timeout: TimeInterval
}

public enum ModelError: Error, Equatable, Sendable {
    case missingAPIKey
    case timeout
    case offline
    case http(status: Int, message: String?)
    case blocked(reason: String)
    case emptyResponse
    case transport(String)
}

/// One interface for every model backend, real or simulated.
public protocol InsightModelClient: Sendable {
    /// Shown under every answer so the member knows where it came from.
    var sourceLabel: String { get }
    var isSimulated: Bool { get }
    /// Returns the model's raw JSON text. Decoding and validation happen in
    /// InsightAssistant so every backend gets the same checks.
    func complete(_ request: ModelRequest) async throws(ModelError) -> String
}
