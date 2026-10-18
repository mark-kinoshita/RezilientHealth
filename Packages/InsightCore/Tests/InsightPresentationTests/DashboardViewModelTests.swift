import Foundation
import InsightCore
import Testing
@testable import InsightPresentation

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
        #expect(viewModel.header?.caption.hasPrefix("Compared with ") == true)
        #expect(viewModel.ask.suggestions.first == "What do you notice about my activity over the last 90 days?")
    }

    @Test func seedingIsUnavailableWithoutASeeder() async {
        let viewModel = makeViewModel(FakeSource(access: .requested))
        #expect(viewModel.sampleScenarios.isEmpty)
    }
}
