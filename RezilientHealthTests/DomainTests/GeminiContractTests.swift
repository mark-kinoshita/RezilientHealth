@testable import RezilientHealth
import Foundation
import Testing

@Suite struct GeminiContractTests {

    @Test func extractsJSONFromGenerateContentEnvelope() throws {
        let envelope = #"""
        {"candidates":[{"content":{"role":"model","parts":[{"text":"{\"status\":\"insufficient_data\",\"takeaway\":\"Here is what the available data shows.\",\"display_metrics\":[],\"observations\":[],\"general_info\":[],\"limitations\":[\"This app doesn't have blood pressure data.\"]}"}]},"finishReason":"STOP"}]}
        """#
        let text = try GeminiClient.parse(data: Data(envelope.utf8), status: 200)
        let answer = try InsightAnswer.decode(text)
        #expect(answer.status == .insufficientData)
        #expect(answer.limitations.count == 1)
    }

    @Test func blockedAndErrorResponsesBecomeTypedFailures() {
        #expect(throws: ModelError.blocked(reason: "SAFETY")) {
            try GeminiClient.parse(data: Data(#"{"promptFeedback":{"blockReason":"SAFETY"}}"#.utf8), status: 200)
        }
        #expect(throws: ModelError.http(status: 429, message: "Quota exceeded")) {
            try GeminiClient.parse(data: Data(#"{"error":{"code":429,"message":"Quota exceeded"}}"#.utf8), status: 429)
        }
    }

    @Test func requestUsesHeaderKeyAndStructuredOutput() throws {
        let client = GeminiClient(apiKey: "test-key", model: "gemini-flash-latest")
        let request = ModelRequest(
            systemInstruction: InsightPrompt.systemInstruction,
            userMessage: InsightPrompt.userMessage(question: "Hi", context: Fixture.stepsOnlyContext),
            context: Fixture.stepsOnlyContext, question: "Hi", timeout: 7
        )
        let urlRequest = try client.makeURLRequest(request)
        #expect(urlRequest.url?.query == nil) // key is not in the URL
        #expect(urlRequest.value(forHTTPHeaderField: "x-goog-api-key") == "test-key")
        #expect(urlRequest.timeoutInterval == 7)
        let body = try #require(JSONSerialization.jsonObject(with: urlRequest.httpBody!) as? [String: Any])
        let config = try #require(body["generationConfig"] as? [String: Any])
        #expect(config["responseMimeType"] as? String == "application/json")
        #expect((config["thinkingConfig"] as? [String: Any])?["thinkingBudget"] as? Int == 0)
        let schema = try #require(config["responseSchema"] as? [String: Any])
        let required = try #require(schema["required"] as? [String])
        #expect(required.contains("takeaway"))
        #expect(required.contains("display_metrics"))
    }

    @Test func capacityErrorIsRetriedOnceThenSucceeds() async throws {
        let valid = #"{"candidates":[{"content":{"parts":[{"text":"{\"status\":\"answered\",\"takeaway\":\"Here is what the available data shows.\",\"display_metrics\":[\"steps\"],\"observations\":[{\"text\":\"Your recorded activity was steady.\",\"metrics\":[\"steps\"]}],\"general_info\":[],\"limitations\":[]}"}]}}]}"#
        let busy = #"{"error":{"code":503,"message":"This model is currently experiencing high demand."}}"#
        let responses = Responses([(503, busy), (200, valid)])
        let client = GeminiClient(apiKey: "k", model: "m", retryDelay: .zero) { request in
            let (status, body) = await responses.next()
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
        let answered = try await InsightAssistant(client: client).ask("How active was I?", context: Fixture.stepsOnlyContext).get()
        #expect(answered.answer.observations.count == 1)
        #expect(await responses.served == 2)
    }

    @Test func thinkingConfigurationCanBeOmittedForOtherModels() throws {
        let client = GeminiClient(apiKey: "test", model: "another-model", thinkingBudget: nil)
        let request = ModelRequest(systemInstruction: InsightPrompt.systemInstruction, userMessage: "test",
                                   context: Fixture.stepsOnlyContext, question: "test", timeout: 20)
        let body = try #require(JSONSerialization.jsonObject(with: client.makeURLRequest(request).httpBody!) as? [String: Any])
        let config = try #require(body["generationConfig"] as? [String: Any])
        #expect(config["thinkingConfig"] == nil)
        #expect(config["responseSchema"] != nil)
    }

    @Test func persistentCapacityErrorFailsWithoutAnAnswer() async {
        let busy = #"{"error":{"code":503,"message":"busy"}}"#
        let responses = Responses([(503, busy), (503, busy), (200, "{}")])
        let client = GeminiClient(apiKey: "k", model: "m", retryDelay: .zero) { request in
            let (status, body) = await responses.next()
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
        let result = await InsightAssistant(client: client).ask("How active was I?", context: Fixture.stepsOnlyContext)
        #expect(result == .failure(.serviceUnavailable))
        #expect(await responses.served == 2) // one retry, not more
    }

    @Test func timeoutFromTransportMapsToTimeout() async {
        let client = GeminiClient(apiKey: "k", model: "m") { _ in throw URLError(.timedOut) }
        let result = await InsightAssistant(client: client).ask("How did I sleep?", context: Fixture.stepsOnlyContext)
        #expect(result == .failure(.timeout))
    }
}

actor Responses {
    private var queue: [(Int, String)]
    private(set) var served = 0
    init(_ queue: [(Int, String)]) { self.queue = queue }
    func next() -> (Int, String) { served += 1; return queue.removeFirst() }
}
