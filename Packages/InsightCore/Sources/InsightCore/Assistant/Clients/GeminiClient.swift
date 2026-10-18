import Foundation

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
