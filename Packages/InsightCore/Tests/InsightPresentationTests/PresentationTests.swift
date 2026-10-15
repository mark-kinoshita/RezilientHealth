import Foundation
import InsightCore
import Testing
@testable import InsightPresentation

/// Protects the wording members see: coverage is always stated, missing data
/// is never described as inactivity, and the model quotes dashboard figures.
@Suite struct MetricCardCopyTests {
    func card(_ snapshot: HealthSnapshot, _ metric: HealthMetric) -> MetricCardState {
        let insight = InsightEngine.insights(for: snapshot).first { $0.metric == metric }!
        return MetricCardPresenter.card(for: insight, series: snapshot.series(metric), access: snapshot.access, calendar: Fixture.calendar)
    }

    @Test func coverageIsStatedAndGapsAreExplicitInTheChart() {
        var steps: [Int: Double] = [-7: 8000, -6: 8000, -4: 8000, -2: 8000, -1: 8000, 0: 1200]
        for offset in -14 ... -8 { steps[offset] = 6000 }
        let card = card(Fixture.snapshot(steps: steps), .steps)

        #expect(card.headline == "Averaging 8,000 steps a day")
        #expect(card.coverageNote?.contains("Based on 5 of 7 days") == true)
        #expect(card.coverageNote?.contains("not counted as zero") == true)
        let missing = card.chart.first { $0.day == Fixture.day(-5) }!
        #expect(missing.value == nil && missing.accessibilityValue == "No data recorded")
        #expect(card.chart.last?.accessibilityValue == "1,200 steps so far today")
    }

    @Test func noDataNeverReadsAsInactivity() {
        let card = card(Fixture.snapshot(access: .requested), .steps)
        #expect(card.isHeadlineMuted)
        #expect(card.detail.contains("doesn't mean nothing happened"))
        #expect(card.coverageNote == nil)
        #expect(card.chart.isEmpty)
    }

    @Test func sparseAndStaleDataSaySo() {
        let steps = Dictionary(uniqueKeysWithValues: (-14 ... -6).map { ($0, 9000.0) })
        let card = card(Fixture.snapshot(steps: steps, latest: [.steps: Fixture.day(-6) + 20 * 3600]), .steps)
        #expect(card.headline == "Not enough recent steps data")
        #expect(card.isStale)
        #expect(card.detail.contains("Last recorded"))
    }

    @Test func modelContextQuotesTheSameFiguresAsTheDashboard() {
        // 7h 10m average. Rounding to 0.1h in the context once made the model
        // say "7h 12m" while the dashboard said "7h 10m".
        let nights = (-6...0).map { offset -> SleepInterval in
            let wake = Fixture.day(offset) + 6 * 3600
            return SleepInterval(start: wake - (7 * 3600 + 10 * 60), end: wake, stage: .asleepCore)
        }
        let snapshot = Fixture.snapshot(sleep: nights)
        let context = Fixture.context(for: snapshot)

        #expect(card(snapshot, .sleep).headline == "Averaging 7h 10m asleep")
        #expect(DisplayFormatter(calendar: Fixture.calendar).hours(context.metrics["sleep"]!.last7Days.average!) == "7h 10m")
    }
}

/// Protects which screen state the member lands in for each access situation.
@MainActor
@Suite struct DashboardViewModelTests {
    func makeViewModel(_ source: FakeSource, seeder: (any SampleDataSeeding)? = nil) -> DashboardViewModel {
        DashboardViewModel(
            source: source,
            assistantOptions: [
                AssistantOption(id: "mock", title: "Mock") { MockModelClient(delay: .zero) },
                AssistantOption(id: "gemini", title: "Gemini") { GeminiClient(apiKey: "", model: "m") },
            ],
            defaultAssistantID: "mock",
            seeder: seeder,
            calendar: Fixture.calendar,
            now: { Fixture.now }
        )
    }

    @Test func notConnectedShowsConnectAndNoCardsOrQuestions() async {
        let viewModel = makeViewModel(FakeSource(access: .notDetermined))
        await viewModel.load()

        #expect(viewModel.notices.map(\.kind) == [.connect])
        #expect(viewModel.cards.isEmpty)
        #expect(viewModel.canAsk == false)
    }

    @Test func connectedButEmptyExplainsAmbiguityInsteadOfShowingZeros() async {
        let viewModel = makeViewModel(FakeSource(access: .requested))
        await viewModel.load()

        #expect(viewModel.notices.map(\.kind) == [.noVisibleData])
        #expect(viewModel.notices.first?.action == .openSettings)
        #expect(viewModel.cards.allSatisfy { $0.chart.isEmpty && $0.isHeadlineMuted })
    }

    @Test func readFailureShowsRetryAndDisablesQuestions() async {
        let source = FakeSource(access: .requested)
        source.fetchError = URLError(.unknown)
        let viewModel = makeViewModel(source)
        await viewModel.load()

        #expect(viewModel.notices.map(\.kind) == [.error])
        #expect(viewModel.notices.first?.action == .retry)
        #expect(viewModel.cards.isEmpty)
        #expect(viewModel.canAsk == false)
    }

    @Test func connectingLoadsDataAndEnablesQuestions() async {
        let source = FakeSource(access: .notDetermined)
        source.raw = RawHealthData(
            dailySteps: Dictionary(uniqueKeysWithValues: (-14 ... -1).map { (Fixture.day($0), 9000.0) }),
            latestSampleDate: [.steps: Fixture.now]
        )
        let viewModel = makeViewModel(source)
        await viewModel.load()
        await viewModel.connect()

        #expect(viewModel.notices.isEmpty)
        #expect(viewModel.cards.first { $0.metric == .steps }?.headline == "Averaging 9,000 steps a day")
        #expect(viewModel.canAsk)
        #expect(viewModel.footnote != nil)
    }

    @Test func switchingAssistantReplacesTheClient() {
        let viewModel = makeViewModel(FakeSource(access: .requested))
        #expect(viewModel.ask.isSimulated)
        viewModel.selectedAssistantID = "gemini"
        #expect(viewModel.ask.isSimulated == false)
    }

    @Test func seedingIsUnavailableWithoutASeeder() async {
        let viewModel = makeViewModel(FakeSource(access: .requested))
        #expect(viewModel.sampleScenarios.isEmpty)
    }
}

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

final class FakeSource: HealthDataSource, @unchecked Sendable {
    var access: HealthAccessState
    var raw = RawHealthData.empty
    var fetchError: Error?

    init(access: HealthAccessState) { self.access = access }

    func accessState() async -> HealthAccessState { access }
    func requestAccess() async throws { access = .requested }
    func fetch(window: DateInterval, calendar: Calendar) async throws -> RawHealthData {
        if let fetchError { throw fetchError }
        return raw
    }
}
