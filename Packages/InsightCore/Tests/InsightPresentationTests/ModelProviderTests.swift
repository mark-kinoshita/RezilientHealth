import Foundation
import InsightCore
import Testing
@testable import InsightPresentation

@MainActor
@Suite struct ModelProviderTests {
    private static let validReply = #"{"status":"answered","takeaway":"Your recorded activity was steady.","display_metrics":["steps"],"observations":[],"general_info":[],"limitations":[]}"#

    @Test func compactPolicyPreservesFactsAndTheExactSentInputIsDisclosed() async throws {
        let original = Fixture.stepsOnlyContext
        let compact = ModelInputPolicy.summaryOnly.prepare(original)
        #expect(compact.metrics.values.allSatisfy { $0.daily.isEmpty })
        #expect(compact.dashboardPatterns == original.dashboardPatterns)
        #expect(compact.window.start == original.window.start)
        #expect(compact.window.end == original.window.end)
        #expect(compact.metrics["steps"]?.currentPeriod == original.metrics["steps"]?.currentPeriod)
        #expect(compact.metrics["steps"]?.previousPeriod == original.metrics["steps"]?.previousPeriod)
        #expect(compact.metrics["steps"]?.stale == original.metrics["steps"]?.stale)
        #expect(compact.window.note.contains("Daily readings are omitted"))

        let capture = ScriptedClient(.success(Self.validReply))
        let client = PolicyClient(base: capture, execution: .onDevice, inputPolicy: .summaryOnly)
        let answered = try await InsightAssistant(client: client).ask("What changed?", context: original).get()
        #expect(capture.calls.first?.context == compact)
        #expect(answered.context == original) // The numerical UI keeps the complete snapshot.
        #expect(answered.contextJSON == compact.jsonString())
        let request = try #require(capture.calls.first)
        #expect(request.systemInstruction == InsightPrompt.instructions(for: .compact))
        #expect(answered.modelInput == "INSTRUCTIONS:\n\(request.systemInstruction)\n\n\(request.userMessage)")
        #expect(!original.metrics["steps"]!.daily.isEmpty)
    }

    @Test func allProvidersStillRejectUncheckedNumericProse() async {
        let invalid = #"{"status":"answered","takeaway":"You averaged 999999 steps.","display_metrics":["steps"],"observations":[],"general_info":[],"limitations":[]}"#
        for execution in [ModelExecution.cloud, .onDevice] {
            let client = PolicyClient(base: ScriptedClient(.success(invalid)), execution: execution, inputPolicy: .summaryOnly)
            let result = await InsightAssistant(client: client).ask("How active was I?", context: Fixture.stepsOnlyContext)
            #expect(result == .failure(.unreadableResponse))
        }
    }

    @Test func summaryPolicyScopesInputsAndRejectsMetricsTheProviderWasNotGiven() async throws {
        let steps = Dictionary(uniqueKeysWithValues: (-14 ... -1).map { ($0, 8000.0) })
        let heartRate = Dictionary(uniqueKeysWithValues: (-14 ... -1).map { ($0, $0 < -7 ? 58.0 : 62.0) })
        let original = Fixture.context(for: Fixture.snapshot(steps: steps, restingHR: heartRate))
        let compact = ModelInputPolicy.summaryOnly.prepare(original, question: "What about my activity?")
        #expect(Set(compact.metrics.keys) == ["steps"])
        #expect(compact.dashboardPatterns.changes.allSatisfy { $0.metric == .steps })
        #expect(compact.dashboardPatterns.sleepSpread == nil)
        let wrongScope = #"{"status":"answered","takeaway":"Your heart rate rose.","display_metrics":["resting_heart_rate","steps"],"observations":[],"general_info":[],"limitations":[]}"#
        let client = PolicyClient(base: ScriptedClient(.success(wrongScope)), execution: .onDevice, inputPolicy: .summaryOnly)
        let answered = try await InsightAssistant(client: client).ask("What about my activity?", context: original).get()
        #expect(answered.answer.displayMetrics == ["steps"])
        #expect(answered.answer.takeaway == InsightAnswer.fallbackTakeaway(for: .answered))
        #expect(answered.context.metrics["resting_heart_rate"] != nil) // Still available locally, never fabricated by the provider.
    }

    @Test func unavailabilityAndContextLimitsKeepTheQuestionWithoutPretendingToAnswer() async {
        for error in [ModelError.unavailable(reason: "The on-device model isn't ready."), .contextLimit] {
            let client = PolicyClient(base: ScriptedClient(.failure(error)), execution: .onDevice, inputPolicy: .summaryOnly)
            let model = AskViewModel(assistant: InsightAssistant(client: client), context: Fixture.stepsOnlyContext)
            #expect(model.sourceDescription.contains("stay on this device"))
            #expect(model.sourceDescription.contains("concise data summaries"))
            await model.ask(suggestion: "What changed?")
            guard case .failed(let question, let message, let canRetry) = model.state else {
                Issue.record("Expected a checked failure"); continue
            }
            #expect(model.draft == question)
            #expect(!canRetry)
            #expect(message.contains(error == .contextLimit ? "choose another model" : "isn't ready"))
        }
    }

    @Test func switchingProvidersKeepsThePendingQuestionButDiscardsHistoryAndLateReplies() async {
        let oldClient = SuspendedModelClient()
        let model = AskViewModel(assistant: InsightAssistant(client: oldClient), context: Fixture.stepsOnlyContext)
        let first = Task { await model.ask(suggestion: "Should I get more steps?") }
        await oldClient.waitForCall(1)
        await oldClient.finish(1, reply: Self.validReply)
        await first.value
        let pending = Task { await model.ask(suggestion: "A walking habit") }
        await oldClient.waitForCall(2)
        let newClient = ScriptedClient(.success(Self.validReply))
        model.replaceAssistant(with: InsightAssistant(client: newClient))
        #expect(model.state == .idle)
        #expect(model.draft == "A walking habit")
        #expect(newClient.calls.isEmpty) // The member must explicitly send to the new provider.
        await model.submit()
        await oldClient.finish(2, reply: Self.validReply)
        await pending.value
        #expect(newClient.calls.first?.history.isEmpty == true)
        guard case .answered(let answer) = model.state else { Issue.record("Expected new provider answer"); return }
        #expect(answer.priorExchangeCount == 0)
        #expect(answer.footer.contains("Scripted"))
    }
}

private struct PolicyClient: InsightModelClient {
    let base: ScriptedClient
    let execution: ModelExecution
    let inputPolicy: ModelInputPolicy
    var promptStyle: ModelPromptStyle { execution == .onDevice ? .compact : .standard }
    var supportsGeneralGuidance: Bool { execution != .onDevice }
    var sourceLabel: String { "Provider contract test" }
    var isSimulated: Bool { false }
    func complete(_ request: ModelRequest) async throws(ModelError) -> String { try await base.complete(request) }
}
