import Foundation
import InsightCore
import Observation

/// A banner above the cards. The view chooses icon and color from `kind`.
public struct DashboardNotice: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable { case error, unavailable, connect, noVisibleData }
    public enum Action: Sendable, Equatable { case retry, connect, openSettings }

    public let kind: Kind
    public let title: String
    public let message: String
    public let action: Action?
    public let actionTitle: String?

    public var id: Kind { kind }
}

public struct DashboardHeader: Sendable, Equatable {
    /// "Oct 8 – Oct 14"
    public let dateRange: String
    /// "Compared with Oct 1 – Oct 7": the period the change chips measure against.
    public let caption: String
}

@MainActor
@Observable
public final class DashboardViewModel {
    public private(set) var isLoading = false
    public private(set) var header: DashboardHeader?
    public private(set) var notices: [DashboardNotice] = []
    public private(set) var cards: [MetricCardState] = []
    public private(set) var footnote: String?
    public var canAsk: Bool { ask.context != nil }

    public private(set) var selectedRange: TimeRange = .week

    /// Reloads with a window of two periods of the new range plus today.
    public func select(_ range: TimeRange) async {
        guard range != selectedRange else { return }
        selectedRange = range
        await load()
    }

    public let ask: AskViewModel
    public let assistantOptions: [AssistantOption]
    public var selectedAssistantID: String {
        didSet { applySelectedAssistant() }
    }

    public var sampleScenarios: [SampleScenario] { seeder?.scenarios ?? [] }

    private let source: any HealthDataSource
    private let seeder: (any SampleDataSeeding)?
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private var loadError: String?

    public init(
        source: any HealthDataSource,
        assistantOptions: [AssistantOption],
        defaultAssistantID: String,
        seeder: (any SampleDataSeeding)? = nil,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        precondition(!assistantOptions.isEmpty, "At least one assistant option is required")
        self.source = source
        self.seeder = seeder
        self.calendar = calendar
        self.now = now
        self.assistantOptions = assistantOptions
        let selected = assistantOptions.first { $0.id == defaultAssistantID } ?? assistantOptions[0]
        self.selectedAssistantID = selected.id
        self.ask = AskViewModel(assistant: InsightAssistant(client: selected.makeClient()), context: nil)
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        loadError = nil
        let range = selectedRange
        let access = await source.accessState()
        let now = now()
        var raw = RawHealthData.empty
        if access == .requested {
            do {
                raw = try await source.fetch(window: SnapshotBuilder.window(now: now, calendar: calendar, range: range), calendar: calendar)
            } catch {
                loadError = "Couldn't read Health data: \(error.localizedDescription)"
            }
        }
        // A newer range selection may have started while this one was loading.
        guard range == selectedRange else { return }
        apply(SnapshotBuilder.build(raw: raw, access: access, now: now, calendar: calendar, range: range))
    }

    public func connect() async {
        do {
            try await source.requestAccess()
        } catch {
            loadError = "Couldn't request Health access: \(error.localizedDescription)"
            notices = [errorNotice()].compactMap { $0 } + notices.filter { $0.kind != .error }
            return
        }
        await load()
    }

    public func seed(_ scenario: SampleScenario) async {
        guard let seeder else { return }
        do {
            if await source.accessState() != .requested { try await source.requestAccess() }
            try await seeder.seed(scenario)
        } catch {
            loadError = "Seeding failed: \(error.localizedDescription)"
            notices = [errorNotice()].compactMap { $0 } + notices.filter { $0.kind != .error }
            return
        }
        await load()
    }

    public func clearSampleData() async {
        try? await seeder?.clear()
        await load()
    }


    private func apply(_ snapshot: HealthSnapshot) {
        let insights = InsightEngine.insights(for: snapshot)
        let context = InsightContextBuilder.build(snapshot: snapshot, insights: insights)
        let format = DisplayFormatter(calendar: calendar)
        let connected = snapshot.access == .requested && loadError == nil

        let range = snapshot.range
        let days = SnapshotBuilder.days(in: snapshot.window, calendar: calendar).dropLast() // today is separate
        let current = days.suffix(range.days)
        let previous = days.dropLast(range.days).suffix(range.days)
        header = DashboardHeader(
            dateRange: "\(format.day(current.first ?? snapshot.window.start)) – \(format.day(current.last ?? snapshot.generatedAt))",
            caption: "Compared with \(format.day(previous.first ?? snapshot.window.start)) – \(format.day(previous.last ?? snapshot.window.start))"
        )
        cards = connected
            ? insights.map { MetricCardPresenter.card(for: $0, series: snapshot.series($0.metric), range: range, access: snapshot.access, calendar: calendar) }
            : []
        footnote = connected
            ? "Updated \(format.time(snapshot.generatedAt)). Gray bars mark days with no data. For general wellness, not medical advice."
            : nil
        ask.range = range
        notices = [errorNotice(), accessNotice(snapshot)].compactMap { $0 }
        // Only offer questions once Health is connected and readable.
        ask.context = connected ? context : nil
    }

    private func errorNotice() -> DashboardNotice? {
        loadError.map {
            DashboardNotice(kind: .error, title: "Something went wrong", message: $0, action: .retry, actionTitle: "Try again")
        }
    }

    private func accessNotice(_ snapshot: HealthSnapshot) -> DashboardNotice? {
        switch snapshot.access {
        case .unavailable:
            return DashboardNotice(kind: .unavailable, title: "Health data isn't available",
                                   message: "This device doesn't support Apple Health.", action: nil, actionTitle: nil)
        case .notDetermined:
            return DashboardNotice(kind: .connect, title: "Connect Apple Health",
                                   message: "Rezilient reads steps, sleep, and resting heart rate to show your trends on this device. A daily summary leaves the device only when you ask a question.",
                                   action: .connect, actionTitle: "Connect")
        case .requested:
            // On iOS, denied read access and "nothing recorded" look identical.
            let nothingVisible = snapshot.series.values.allSatisfy { !$0.hasAnyData && $0.lastSampleDate == nil }
            guard nothingVisible, loadError == nil else { return nil }
            return DashboardNotice(kind: .noVisibleData, title: "We can't see any health data",
                                   message: "Either access is turned off, or no device has recorded anything yet. iOS doesn't tell apps which. You can check under Settings › Health › Data Access & Devices.",
                                   action: .openSettings, actionTitle: "Open Settings")
        }
    }

    private func applySelectedAssistant() {
        guard let option = assistantOptions.first(where: { $0.id == selectedAssistantID }) else { return }
        ask.assistant = InsightAssistant(client: option.makeClient())
    }
}
