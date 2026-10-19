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
        let valid = #"{"status":"answered","takeaway":"Here is what the available data shows.","display_metrics":["steps"],"observations":[{"text":"Your recorded activity was steady.","metrics":["steps"]}],"general_info":[],"limitations":[]}"#
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

    @Test func followUpsCarryValidatedHistoryAndPinTheHealthSnapshot() async throws {
        let client = ScriptedClient(.success(Self.validReply), .success(Self.validReply))
        let original = Fixture.stepsOnlyContext
        let model = AskViewModel(assistant: InsightAssistant(client: client), context: original)
        await model.ask(suggestion: "Should I get more steps?")
        model.context = Fixture.context(for: Fixture.snapshot(steps: [-1: 200]))
        await model.ask(suggestion: "I want to build a walking habit")
        #expect(client.calls[1].history.map(\.question) == ["Should I get more steps?"])
        #expect(client.calls[1].context == original)
        #expect(client.calls[1].userMessage.contains("RECENT_CONVERSATION:"))
        guard case .answered(let answer) = model.state else { Issue.record("Expected answer"); return }
        #expect(answer.priorExchangeCount == 1)
        #expect(answer.modelInput.contains("Should I get more steps?"))
        #expect(answer.dataNotes.contains { $0.contains("same health snapshot") })
    }

    @Test func failedTurnsAreNotAddedAndRetryDoesNotDuplicateHistory() async {
        let client = ScriptedClient(.success(Self.validReply), .failure(.timeout), .success(Self.validReply))
        let model = AskViewModel(assistant: InsightAssistant(client: client), context: Fixture.stepsOnlyContext)
        await model.ask(suggestion: "Should I get more steps?")
        await model.ask(suggestion: "A walking habit")
        await model.retry()
        #expect(client.calls[1].history == client.calls[2].history)
        #expect(client.calls[2].history.count == 1)
        #expect(client.calls[2].question == "A walking habit")
    }

    @Test func historyIsBoundedAndStartingOverUsesTheLatestSnapshot() async {
        let client = ScriptedClient(.success(Self.validReply), .success(Self.validReply), .success(Self.validReply),
                                    .success(Self.validReply), .success(Self.validReply), .success(Self.validReply))
        let model = AskViewModel(assistant: InsightAssistant(client: client), context: Fixture.stepsOnlyContext)
        for index in 1...5 { await model.ask(suggestion: "Question \(index)") }
        #expect(client.calls[4].history.map(\.question) == ["Question 2", "Question 3", "Question 4"])
        let fresh = Fixture.context(for: Fixture.snapshot(steps: [-1: 200]))
        model.context = fresh
        model.startOver()
        await model.ask(suggestion: "Start fresh")
        #expect(client.calls[5].history.isEmpty)
        #expect(client.calls[5].context == fresh)
    }

    private static let validReply = #"{"status":"answered","takeaway":"Your recorded activity was steady.","display_metrics":["steps"],"observations":[],"general_info":[],"limitations":[]}"#

    @Test func simulatedGoalFollowUpUsesTheEarlierQuestion() async {
        let model = AskViewModel(assistant: InsightAssistant(client: MockModelClient(delay: .zero)), context: Fixture.stepsOnlyContext)
        await model.ask(suggestion: "Should I get more steps?")
        await model.ask(suggestion: "A walking habit")
        guard case .answered(let answer) = model.state else { Issue.record("Expected answer"); return }
        #expect(answer.priorExchangeCount == 1)
        #expect(answer.takeaway == "Let's focus on consistency rather than a personal step target.")
        #expect(answer.metricRows.map(\.metric) == [.steps])
        #expect(answer.generalInfo.first?.contains("repeatable time or cue") == true)
    }

    @Test func startingOverWhileLoadingRejectsTheLateAnswerEvenIfTheClientIgnoresCancellation() async {
        let client = SuspendedModelClient()
        let model = AskViewModel(assistant: InsightAssistant(client: client), context: Fixture.stepsOnlyContext)
        let old = Task { await model.ask(suggestion: "Old question") }
        await client.waitForCall(1)
        model.startOver()
        let latest = Task { await model.ask(suggestion: "New question") }
        await client.waitForCall(2)
        await client.finish(2, reply: Self.validReply)
        await latest.value
        await client.finish(1, reply: Self.validReply)
        await old.value
        guard case .answered(let answer) = model.state else { Issue.record("Expected the latest answer"); return }
        #expect(answer.question == "New question")
        #expect(answer.priorExchangeCount == 0)
    }

    @Test func losingReadableDataClearsPinnedHistoryAndRejectsAnInFlightAnswer() async {
        let client = SuspendedModelClient()
        let model = AskViewModel(assistant: InsightAssistant(client: client), context: Fixture.stepsOnlyContext)
        let old = Task { await model.ask(suggestion: "Old question") }
        await client.waitForCall(1)
        model.context = nil
        await client.finish(1, reply: Self.validReply)
        await old.value
        #expect(model.state == .idle)
        await model.ask(suggestion: "Can I still ask?")
        guard case .failed(let question, _, _) = model.state else { Issue.record("Expected unavailable data failure"); return }
        #expect(question == "Can I still ask?")
        #expect(model.draft == question)
    }

    @Test func clinicianStatusShowsBanner() async {
        let reply = #"{"status":"needs_clinician","takeaway":"Here is what the available data shows.","display_metrics":[],"observations":[],"general_info":["Talk to a clinician."],"limitations":[]}"#
        let model = AskViewModel(assistant: InsightAssistant(client: ScriptedClient(.success(reply))), context: Fixture.stepsOnlyContext)
        await model.ask(suggestion: "Do I have sleep apnea?")

        guard case .answered(let answer) = model.state else {
            Issue.record("expected an answer, got \(model.state)"); return
        }
        #expect(answer.banner == .needsClinician)
        #expect(answer.followUps.isEmpty)
    }
}
