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

// MARK: - Gemini

public struct GeminiClient: InsightModelClient {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    let apiKey: String
    let model: String
    let transport: Transport
    let retryDelay: Duration

    public init(apiKey: String, model: String, retryDelay: Duration = .seconds(1), transport: Transport? = nil) {
        self.apiKey = apiKey
        self.model = model
        self.retryDelay = retryDelay
        self.transport = transport ?? { request in try await URLSession.shared.data(for: request) }
    }

    public var sourceLabel: String { "Gemini (\(model))" }
    public var isSimulated: Bool { false }

    public func complete(_ request: ModelRequest) async throws(ModelError) -> String {
        guard !apiKey.isEmpty else { throw .missingAPIKey }
        let urlRequest = try makeURLRequest(request)
        do {
            return try await send(urlRequest)
        } catch .http(let status, _) where [429, 503].contains(status) {
            // Capacity errors come back in under a second and are usually
            // transient; one retry is cheap. Anything else fails immediately.
            try? await Task.sleep(for: retryDelay)
            return try await send(urlRequest)
        }
    }

    private func send(_ urlRequest: URLRequest) async throws(ModelError) -> String {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(urlRequest)
        } catch let error as URLError {
            switch error.code {
            case .timedOut: throw .timeout
            case .notConnectedToInternet, .networkConnectionLost: throw .offline
            default: throw .transport(error.localizedDescription)
            }
        } catch {
            throw .transport(String(describing: error))
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return try Self.parse(data: data, status: status)
    }

    func makeURLRequest(_ request: ModelRequest) throws(ModelError) -> URLRequest {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
            throw .transport("Invalid model name")
        }
        var urlRequest = URLRequest(url: url, timeoutInterval: request.timeout)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": request.systemInstruction]]],
            "contents": [["role": "user", "parts": [["text": request.userMessage]]]],
            "generationConfig": [
                "temperature": 0.2,
                // Thinking took up to ~60s in testing vs ~1.5s without; the
                // reasoning is already done on device (InsightEngine).
                "thinkingConfig": ["thinkingBudget": 0],
                "responseMimeType": "application/json",
                "responseSchema": InsightPrompt.responseSchema,
            ],
        ]
        urlRequest.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }

    /// Extracts the JSON text from a generateContent envelope.
    static func parse(data: Data, status: Int) throws(ModelError) -> String {
        struct Envelope: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable { let text: String? }
                    let parts: [Part]?
                }
                let content: Content?
                let finishReason: String?
            }
            struct Feedback: Decodable { let blockReason: String? }
            struct APIError: Decodable { let message: String? }
            let candidates: [Candidate]?
            let promptFeedback: Feedback?
            let error: APIError?
        }

        let envelope = try? JSONDecoder().decode(Envelope.self, from: data)
        guard (200..<300).contains(status) else {
            throw .http(status: status, message: envelope?.error?.message)
        }
        if let reason = envelope?.promptFeedback?.blockReason {
            throw .blocked(reason: reason)
        }
        guard let candidate = envelope?.candidates?.first else { throw .emptyResponse }
        if let reason = candidate.finishReason, ["SAFETY", "RECITATION", "PROHIBITED_CONTENT", "BLOCKLIST", "SPII"].contains(reason) {
            throw .blocked(reason: reason)
        }
        let text = (candidate.content?.parts ?? []).compactMap(\.text).joined()
        guard !text.isEmpty else { throw .emptyResponse }
        return text
    }
}

// MARK: - Deterministic mock

/// Clearly-labeled stand-in used when no API key is configured, in tests, and
/// to reproduce failures on demand. It applies the same rules as the prompt
/// using simple keyword checks, which is good enough to demo boundary behavior
/// but is not how real answers are produced.
public struct MockModelClient: InsightModelClient {
    public enum Behavior: String, CaseIterable, Sendable, Identifiable {
        case normal, timeout, serverError, malformed
        public var id: String { rawValue }
    }

    public let behavior: Behavior
    let delay: Duration

    public init(behavior: Behavior = .normal, delay: Duration = .milliseconds(600)) {
        self.behavior = behavior
        self.delay = delay
    }

    public var sourceLabel: String { "Simulated response (mock, no AI)" }
    public var isSimulated: Bool { true }

    public func complete(_ request: ModelRequest) async throws(ModelError) -> String {
        try? await Task.sleep(for: delay)
        switch behavior {
        case .timeout: throw .timeout
        case .serverError: throw .http(status: 503, message: "Simulated outage")
        case .malformed: return "Sure! Your steps look great this week."
        case .normal: break
        }
        let answer = Self.answer(question: request.question, context: request.context)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return String(decoding: (try? encoder.encode(answer)) ?? Data(), as: UTF8.self)
    }

    static let clinicalTerms = ["diagnos", "disease", "disorder", "apnea", "afib", "arrhythmia", "medication", "medicine", "dose", "prescri", "treat", "should i take", "is something wrong", "am i sick"]
    static let untrackedTerms: [(String, String)] = [
        ("hrv", "heart rate variability"), ("variability", "heart rate variability"),
        ("calorie", "calories"), ("blood pressure", "blood pressure"), ("glucose", "blood glucose"),
        ("weight", "weight"), ("stress", "stress"), ("diet", "nutrition"), ("food", "nutrition"),
        ("workout", "workouts"), ("running", "workouts"), ("period", "menstrual cycle"),
    ]

    static func answer(question: String, context: InsightContext) -> InsightAnswer {
        let q = question.lowercased()
        let observations = HealthMetric.allCases.compactMap { metric -> InsightAnswer.Observation? in
            guard let m = context.metrics[metric.rawValue], m.last7Days.sufficient, let avg = m.last7Days.average else { return nil }
            var text = "Over \(m.last7Days.start ?? "?") to \(m.last7Days.end ?? "?"), your \(metric.displayName.lowercased()) averaged \(formatted(avg, metric)) on \(m.last7Days.daysWithData) of \(m.last7Days.daysInPeriod) days with data"
            if m.previous7Days.sufficient, let prior = m.previous7Days.average {
                text += ", compared with \(formatted(prior, metric)) the week before"
            }
            return .init(text: text + ".", metrics: [metric.rawValue])
        }
        let gaps = context.metrics.compactMap { key, m -> String? in
            let missing = m.last7Days.daysInPeriod - m.last7Days.daysWithData
            return missing > 0 ? "\(HealthMetric(rawValue: key)?.displayName ?? key): \(missing) of the last \(m.last7Days.daysInPeriod) days have no data, so they're left out." : nil
        }.sorted()

        if clinicalTerms.contains(where: q.contains) {
            return InsightAnswer(
                status: .needsClinician,
                observations: Array(observations.prefix(2)),
                generalInfo: ["Wearable trends can't diagnose a condition or guide treatment. A clinician can look at these numbers alongside your history."],
                limitations: ["This app doesn't make diagnoses or medication recommendations."] + gaps
            )
        }
        if let (_, missing) = untrackedTerms.first(where: { q.contains($0.0) }) {
            return InsightAnswer(
                status: .insufficientData,
                observations: [],
                generalInfo: [],
                limitations: ["This app doesn't have \(missing) data, so it can't answer that from your data. It currently reads steps, sleep, and resting heart rate."]
            )
        }
        if observations.isEmpty {
            return InsightAnswer(
                status: .insufficientData, observations: [], generalInfo: [],
                limitations: ["There isn't enough recent data to answer that. Averages need at least 4 of 7 days."] + gaps
            )
        }
        return InsightAnswer(
            status: .answered,
            observations: observations,
            generalInfo: ["Many adults aim for 7 or more hours of sleep, and regular daily movement supports heart health."],
            limitations: gaps
        )
    }

    private static func formatted(_ value: Double, _ metric: HealthMetric) -> String {
        switch metric {
        case .steps: "\(Int(value.rounded()).formatted()) steps"
        case .sleep: Formatting.hours(value)
        case .restingHeartRate: "\(Int(value.rounded())) bpm"
        }
    }
}
