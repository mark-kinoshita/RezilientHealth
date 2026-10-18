import Foundation
import InsightCore
import Testing
@testable import InsightPresentation

/// Protects the failure contract: never lose the question, never show an
/// unchecked answer.
@MainActor
@Suite struct AskViewModelTests {
    @Test func timeoutKeepsTheQuestionAndShowsNoAnswer() async {
        let model = AskViewModel(assistant: InsightAssistant(client: ScriptedClient(.failure(.timeout))), context: Fixture.stepsOnlyContext)
        model.draft = "What do you notice about my activity this week?"

        await model.submit()

        guard case .failed(let question, let message, let canRetry) = model.state else {
            Issue.record("expected failure, got \(model.state)"); return
        }
        #expect(question == "What do you notice about my activity this week?")
        #expect(message.contains("took too long"))
        #expect(canRetry)
        #expect(model.draft == "What do you notice about my activity this week?")
    }

    @Test func retryAfterFailureResendsTheSameQuestion() async {
        let valid = #"{"status":"answered","observations":[{"text":"You averaged 8,000 steps.","metrics":["steps"]}],"general_info":[],"limitations":[]}"#
        let client = ScriptedClient(.failure(.http(status: 503, message: nil)), .success(valid))
        let model = AskViewModel(assistant: InsightAssistant(client: client), context: Fixture.stepsOnlyContext)
        model.draft = "How active was I?"

        await model.submit()
        await model.retry()

        guard case .answered(let answer) = model.state else {
            Issue.record("expected an answer, got \(model.state)"); return
        }
        #expect(answer.question == "How active was I?")
        #expect(answer.observations.first?.metrics == [.steps])
        #expect(client.calls.map(\.question) == ["How active was I?", "How active was I?"])
        #expect(model.draft.isEmpty)
    }

    @Test func clinicianStatusShowsBanner() async {
        let reply = #"{"status":"needs_clinician","observations":[],"general_info":["Talk to a clinician."],"limitations":[]}"#
        let model = AskViewModel(assistant: InsightAssistant(client: ScriptedClient(.success(reply))), context: Fixture.stepsOnlyContext)
        await model.ask(suggestion: "Do I have sleep apnea?")

        guard case .answered(let answer) = model.state else {
            Issue.record("expected an answer, got \(model.state)"); return
        }
        #expect(answer.banner == .needsClinician)
    }
}
