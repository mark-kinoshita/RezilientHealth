@testable import RezilientHealth
import Foundation
import Testing

/// Protects which screen state the member lands in for each access situation.
@MainActor
@Suite struct DashboardViewModelTests {
    func makeViewModel(_ source: any HealthDataSource, seeder: (any SampleDataSeeding)? = nil) -> DashboardViewModel {
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

    @Test func launchStaysLoadingUntilDataArrivesAndRefreshKeepsTheDashboard() async {
        let source = PausedDashboardSource()
        let model = makeViewModel(source)
        // No blank frame before the view's initial task starts.
        #expect(model.isInitialLoading)
        #expect(!model.canAsk)

        let initial = Task { await model.load() }
        await source.waitForFetch()
        #expect(model.isLoading)
        #expect(model.isInitialLoading)
        #expect(model.header == nil)
        await source.finish(.success(.empty))
        await initial.value
        #expect(!model.isLoading)
        #expect(!model.isInitialLoading)
        #expect(model.cards.count == 3)

        let refresh = Task { await model.load() }
        await source.waitForFetch()
        #expect(model.isLoading)
        #expect(!model.isInitialLoading)
        #expect(model.cards.count == 3)
        await source.finish(.failure(URLError(.networkConnectionLost)))
        await refresh.value
        #expect(!model.isLoading)
        #expect(!model.isInitialLoading)
        #expect(model.notices.map(\.kind) == [.error])
    }

    private func recordedSteps(_ count: Double) -> RawHealthData {
        RawHealthData(dailySteps: Dictionary(uniqueKeysWithValues: (-180 ... -1).map { (Fixture.day($0), count) }),
                      latestSampleDate: [.steps: Fixture.now])
    }

    @Test func obsoleteReadFailureCannotClearLoadingOrPolluteTheNewerResult() async {
        let source = OrderedDashboardSource()
        let model = makeViewModel(source)
        let old = Task { await model.load() }
        await source.waitForFetch(1)
        let latest = Task { await model.load() }
        await source.waitForFetch(2)
        await source.finish(1, result: .failure(URLError(.unknown)))
        await old.value
        #expect(model.isLoading)
        #expect(model.notices.isEmpty)
        await source.finish(2, result: .success(recordedSteps(9000)))
        await latest.value
        #expect(!model.isLoading)
        #expect(model.notices.isEmpty)
        #expect(model.cards.first { $0.metric == .steps }?.value == "9,000")
    }

    @Test func weekMonthWeekKeepsTheNewestWeekAndHidesPreviousRangeWhileLoading() async {
        let source = OrderedDashboardSource()
        let model = makeViewModel(source)
        let firstWeek = Task { await model.load() }
        await source.waitForFetch(1)
        let month = Task { await model.select(.month) }
        await source.waitForFetch(2)
        #expect(model.periodTitle == "Your month")
        #expect(model.header == nil && model.cards.isEmpty)
        #expect(!model.canAsk)
        let latestWeek = Task { await model.select(.week) }
        await source.waitForFetch(3)
        #expect(model.periodTitle == "Your week")
        await source.finish(3, result: .success(recordedSteps(9000)))
        await latestWeek.value
        await source.finish(2, result: .failure(URLError(.unknown)))
        await month.value
        await source.finish(1, result: .success(recordedSteps(2000)))
        await firstWeek.value
        #expect(model.cards.first { $0.metric == .steps }?.value == "9,000")
        #expect(model.notices.isEmpty)
        #expect(!model.isLoading)
        #expect(model.ask.context?.window.periodDays == 7)
    }

    @Test func changingRangeInvalidatesAnInFlightQuestionAndItsSnapshot() async {
        let source = FakeSource(access: .requested)
        source.raw = recordedSteps(8000)
        let client = SuspendedModelClient()
        let model = DashboardViewModel(source: source, assistantOptions: [AssistantOption(id: "paused", title: "Paused") { client }],
                                       defaultAssistantID: "paused", calendar: Fixture.calendar, now: { Fixture.now })
        await model.load()
        let oldQuestion = Task { await model.ask.ask(suggestion: "What changed this week?") }
        await client.waitForCall(1)
        await model.select(.month)
        await client.finish(1, reply: Self.validReply)
        await oldQuestion.value
        #expect(model.ask.state == .idle)
        let newQuestion = Task { await model.ask.ask(suggestion: "What changed this month?") }
        await client.waitForCall(2)
        #expect(await client.request(2).context.window.periodDays == 30)
        #expect(await client.request(2).history.isEmpty)
        await client.finish(2, reply: Self.validReply)
        await newQuestion.value
        await model.select(.quarter)
        #expect(model.periodTitle == "Your last 90 days")
    }

    private static let validReply = #"{"status":"answered","takeaway":"Your recorded activity was steady.","display_metrics":["steps"],"observations":[],"general_info":[],"limitations":[]}"#

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
        #expect(viewModel.notices.first?.action == .openHealth)
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

    @Test func selectingARangeRefetchesTwoPeriodsAndUpdatesSuggestions() async {
        let source = FakeSource(access: .requested)
        let viewModel = makeViewModel(source)
        await viewModel.load()
        await viewModel.select(.quarter)

        let window = source.fetchedWindows.last!
        let days = Fixture.calendar.dateComponents([.day], from: window.start, to: Fixture.calendar.startOfDay(for: window.end)).day!
        #expect(days == 180)                                   // 90 + 90 before today
        #expect(viewModel.selectedRange == .quarter)
        #expect(viewModel.header?.dateRange.isEmpty == false)
        #expect(viewModel.header?.caption.hasPrefix("vs. ") == true)
        #expect(viewModel.ask.suggestions.first == "What stood out over the last 90 days?")
    }

    @Test func seedingIsUnavailableWithoutASeeder() async {
        let viewModel = makeViewModel(FakeSource(access: .requested))
        #expect(viewModel.sampleScenarios.isEmpty)
    }
}


/// A suspended platform read makes lifecycle assertions deterministic.
private actor PausedDashboardSource: HealthDataSource {
    private var pending: CheckedContinuation<RawHealthData, any Error>?
    private var started: CheckedContinuation<Void, Never>?

    func accessState() async -> HealthAccessState { .requested }
    func requestAccess() async throws {}
    func fetch(window: DateInterval, calendar: Calendar) async throws -> RawHealthData {
        try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            started?.resume()
            started = nil
        }
    }

    func waitForFetch() async {
        if pending != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func finish(_ result: Result<RawHealthData, any Error>) {
        let continuation = pending
        pending = nil
        continuation?.resume(with: result)
    }
}
