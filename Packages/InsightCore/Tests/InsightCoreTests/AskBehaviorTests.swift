import Foundation
import Testing
@testable import InsightCore

/// Protects the question flow's grounding and failure contract.
@Suite struct AskBehaviorTests {

    @Test func freeTextReplyIsNeverShownAsAnAnswer() async {
        let client = ScriptedClient(.success("Sure! Your steps look great this week."))
        let result = await InsightAssistant(client: client).ask("How am I doing?", context: Fixture.stepsOnlyContext)
        #expect(result == .failure(.unreadableResponse))
    }

    @Test func observationsNotBackedByAvailableDataAreRemovedAndDisclosed() throws {
        // Only steps have data; the model claims something about sleep and
        // makes an uncited claim. Both must go; general info stays separate.
        let answer = InsightAnswer(
            status: .answered,
            observations: [
                .init(text: "You averaged 8,000 steps a day.", metrics: ["steps"]),
                .init(text: "Your sleep improved.", metrics: ["sleep"]),
                .init(text: "You seem stressed.", metrics: []),
            ],
            generalInfo: ["Regular movement supports heart health."],
            limitations: []
        )
        let (validated, removed) = try AnswerValidator.validate(answer, context: Fixture.stepsOnlyContext)

        #expect(removed == 2)
        #expect(validated.observations.map(\.metrics) == [["steps"]])
        #expect(validated.generalInfo == ["Regular movement supports heart health."])
        #expect(validated.limitations.last?.contains("2 statements were hidden") == true)
    }

    @Test func possibleEmergencyIsAnsweredLocallyWithoutCallingTheModel() async throws {
        let client = ScriptedClient()
        let result = await InsightAssistant(client: client).ask("I have chest pain and my heart rate is high", context: Fixture.stepsOnlyContext)

        #expect(client.calls.isEmpty)
        let answered = try result.get()
        #expect(answered.answer.status == .needsClinician)
        #expect(answered.answer.generalInfo.first?.contains("911") == true)
    }

    @Test func deterministicMockRefusesDiagnosisAndUntrackedData() {
        let context = Fixture.stepsOnlyContext
        #expect(MockModelClient.answer(question: "Do I have sleep apnea?", context: context).status == .needsClinician)
        #expect(MockModelClient.answer(question: "What's my blood pressure trend?", context: context).status == .insufficientData)
        #expect(MockModelClient.answer(question: "What do you notice about my activity this week?", context: context).status == .answered)
    }
}

@Suite struct GeminiContractTests {

    @Test func extractsJSONFromGenerateContentEnvelope() throws {
        let envelope = #"""
        {"candidates":[{"content":{"role":"model","parts":[{"text":"{\"status\":\"insufficient_data\",\"observations\":[],\"general_info\":[],\"limitations\":[\"This app doesn't have blood pressure data.\"]}"}]},"finishReason":"STOP"}]}
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
        #expect(config["responseSchema"] != nil)
    }

    @Test func capacityErrorIsRetriedOnceThenSucceeds() async throws {
        let valid = #"{"candidates":[{"content":{"parts":[{"text":"{\"status\":\"answered\",\"observations\":[{\"text\":\"You averaged 8,000 steps.\",\"metrics\":[\"steps\"]}],\"general_info\":[],\"limitations\":[]}"}]}}]}"#
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
