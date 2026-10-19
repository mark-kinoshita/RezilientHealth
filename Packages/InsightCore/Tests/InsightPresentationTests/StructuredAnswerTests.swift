import Foundation
import InsightCore
import Testing
@testable import InsightPresentation

@MainActor
@Suite struct StructuredAnswerTests {
    @Test func stepsAdviceAnswersTheQuestionWithoutRepeatingTheDashboard() async throws {
        let steps = Dictionary(uniqueKeysWithValues: (-14 ... -1).map { ($0, $0 < -7 ? 8000.0 : 6500.0) })
        let heartRate = Dictionary(uniqueKeysWithValues: (-14 ... -1).map { ($0, $0 < -7 ? 58.0 : 62.0) })
        let sleep = (-14 ... -1).map { day in
            SleepInterval(start: Fixture.day(day), end: Fixture.day(day).addingTimeInterval((day < -7 ? 8 : 6.5) * 3600), stage: .asleepCore)
        }
        let viewModel = AskViewModel(
            assistant: InsightAssistant(client: MockModelClient(delay: .zero)),
            context: Fixture.context(for: Fixture.snapshot(steps: steps, restingHR: heartRate, sleep: sleep))
        )
        // Include the wording from the reported failure, as well as a clearer variant.
        for question in ["Should he getting more steps in or this a good amount?", "Am I getting enough steps?"] {
            await viewModel.ask(suggestion: question)
            guard case .answered(let answer) = viewModel.state else { Issue.record("Expected answer"); return }
            #expect(answer.banner == nil)
            #expect(answer.takeaway == "Your step count alone doesn't tell us whether you need more activity.")
            #expect(answer.metricRows.map(\.metric) == [.steps])
            #expect(answer.metricRows.first?.value == "6,500/day")
            #expect(answer.observations.isEmpty)
            #expect(answer.generalInfo == ["Are you aiming to build a walking habit or return to your usual activity?"])
        }
    }

    @Test func adviceQuestionsStillRespectMissingDataAndClinicalBoundaries() async throws {
        let viewModel = AskViewModel(
            assistant: InsightAssistant(client: MockModelClient(delay: .zero)),
            context: Fixture.context(for: Fixture.snapshot(steps: [-1: 6500]))
        )
        await viewModel.ask(suggestion: "Should I get more steps?")
        guard case .answered(let sparse) = viewModel.state else { Issue.record("Expected sparse answer"); return }
        #expect(sparse.banner == .insufficientData)
        #expect(sparse.metricRows.first?.value == "Not enough data")

        viewModel.context = Fixture.stepsOnlyContext
        await viewModel.ask(suggestion: "Should I get more steps to treat my disease?")
        guard case .answered(let clinical) = viewModel.state else { Issue.record("Expected clinical boundary"); return }
        #expect(clinical.banner == .needsClinician)
        #expect(clinical.followUps.isEmpty)
    }

    private func model(context: InsightContext, keys: [String], takeaway: String = "Your recorded patterns changed.") throws -> AskViewModel {
        let reply = InsightAnswer(status: .answered, takeaway: takeaway, displayMetrics: keys,
                                  observations: [], generalInfo: [], limitations: [])
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let json = String(decoding: try encoder.encode(reply), as: UTF8.self)
        return AskViewModel(assistant: InsightAssistant(client: ScriptedClient(.success(json))), context: context)
    }

    @Test func rowsUseCapturedContextNotExtraNumbersFromTheModelOrLaterRefreshes() async throws {
        var steps = Dictionary(uniqueKeysWithValues: (-14 ... -1).map { ($0, $0 < -7 ? 6000.0 : 8000.0) })
        steps[0] = 999_999 // In progress; must never affect a completed-period row.
        let context = Fixture.context(for: Fixture.snapshot(steps: steps))
        let json = #"{"status":"answered","takeaway":"Your activity rose.","display_metrics":["steps"],"current_average":999999,"observations":[],"general_info":[],"limitations":[]}"#
        let viewModel = AskViewModel(assistant: InsightAssistant(client: ScriptedClient(.success(json))), context: context)
        await viewModel.ask(suggestion: "What changed?")
        guard case .answered(let answer) = viewModel.state else { Issue.record("Expected answer"); return }
        let row = try #require(answer.metricRows.first)
        #expect(row.value == "8,000/day")
        #expect(row.previous == "6,000/day before")
        #expect(row.coverage == "7/7 days")
        #expect(row.direction == .up)
        #expect(answer.periodLabel?.contains("Oct 8") == true)
        #expect(answer.dataNotes.contains { $0.contains("Today's values") })

        viewModel.context = Fixture.context(for: Fixture.snapshot(steps: [-1: 100]))
        guard case .answered(let retained) = viewModel.state else { Issue.record("Answer disappeared"); return }
        #expect(retained.metricRows == answer.metricRows)
    }

    @Test func sparseCurrentPeriodNeverDisplaysItsRawAverageAndUsesInsufficientBanner() async throws {
        var steps: [Int: Double] = [-2: 8000, -1: 8000]
        for day in -14 ... -8 { steps[day] = 6000 }
        let viewModel = try model(context: Fixture.context(for: Fixture.snapshot(steps: steps)), keys: ["steps"])
        await viewModel.ask(suggestion: "What changed?")
        guard case .answered(let answer) = viewModel.state else { Issue.record("Expected answer"); return }
        #expect(answer.banner == .insufficientData)
        #expect(answer.metricRows.first?.value == "Not enough data")
        #expect(answer.metricRows.first?.coverage == "2/7 days")
        #expect(answer.metricRows.first?.direction == nil)
        #expect(answer.followUps.isEmpty)
    }

    @Test func insufficientPriorDataNeverProducesAComparisonOrZero() async throws {
        var steps = Dictionary(uniqueKeysWithValues: (-7 ... -1).map { ($0, 8000.0) })
        steps[-8] = 5000
        let viewModel = try model(context: Fixture.context(for: Fixture.snapshot(steps: steps)), keys: ["steps"])
        await viewModel.ask(suggestion: "What changed?")
        guard case .answered(let answer) = viewModel.state else { Issue.record("Expected answer"); return }
        #expect(answer.metricRows.first?.value == "8,000/day")
        #expect(answer.metricRows.first?.previous == "Not enough earlier data")
        #expect(answer.metricRows.first?.direction == nil)
        #expect(answer.dataNotes.contains { $0.contains("earlier period") })
    }

    @Test func unavailableAndDuplicateMetricSelectionsCannotCreateExtraRows() async throws {
        let viewModel = try model(context: Fixture.stepsOnlyContext, keys: ["sleep", "steps", "steps", "blood_pressure"])
        await viewModel.ask(suggestion: "What changed?")
        guard case .answered(let answer) = viewModel.state else { Issue.record("Expected answer"); return }
        #expect(answer.metricRows.map(\.metric) == [.steps])
        #expect(answer.dataNotes.contains { $0.contains("omitted") })
        #expect(answer.takeaway == InsightAnswer.fallbackTakeaway(for: .answered))
    }

    @Test func staleRowsKeepTheirWarningAndOfferNoFreshDataFollowUp() async throws {
        let steps = Dictionary(uniqueKeysWithValues: (-14 ... -1).map { ($0, 8000.0) })
        let snapshot = Fixture.snapshot(steps: steps, latest: [.steps: Fixture.day(-4)])
        let viewModel = try model(context: Fixture.context(for: snapshot), keys: ["steps"])
        await viewModel.ask(suggestion: "What changed?")
        guard case .answered(let answer) = viewModel.state else { Issue.record("Expected answer"); return }
        #expect(answer.metricRows.first?.isStale == true)
        #expect(answer.dataNotes.contains { $0.contains("last recording") })
        #expect(answer.followUps.isEmpty)
    }

    @Test func numberBearingModelTextFailsWithoutLosingTheQuestion() async throws {
        let viewModel = try model(context: Fixture.stepsOnlyContext, keys: ["steps"], takeaway: "You averaged 999999 steps.")
        await viewModel.ask(suggestion: "How active was I?")
        guard case .failed(_, _, let retry) = viewModel.state else { Issue.record("Expected checked failure"); return }
        #expect(retry)
        #expect(viewModel.draft == "How active was I?")
    }

    @Test func sleepRowsMatchDashboardMinutesAndFollowUpsOnlyUseSelectedMetrics() async throws {
        let sleep = (-14 ... -1).map { day in
            SleepInterval(start: Fixture.day(day), end: Fixture.day(day).addingTimeInterval((day < -7 ? 8 : 6.5) * 3600), stage: .asleepCore)
        }
        let snapshot = Fixture.snapshot(sleep: sleep)
        let viewModel = try model(context: Fixture.context(for: snapshot), keys: ["sleep"])
        await viewModel.ask(suggestion: "What changed in my sleep?")
        guard case .answered(let answer) = viewModel.state else { Issue.record("Expected answer"); return }
        let row = try #require(answer.metricRows.first)
        let insight = try #require(InsightEngine.insights(for: snapshot).first { $0.metric == .sleep })
        let dashboardCard = MetricCardPresenter.card(for: insight, series: snapshot.series(.sleep), range: .week,
                                                     access: .requested, calendar: Fixture.calendar)
        #expect(row.value == dashboardCard.value)
        #expect(row.changeText == "1h 30m")
        #expect(row.direction == .down)
        #expect(answer.followUps.map(\.metric) == [.sleep])
        #expect(answer.followUps.first?.question.contains("last 7 days") == true)
    }
}
