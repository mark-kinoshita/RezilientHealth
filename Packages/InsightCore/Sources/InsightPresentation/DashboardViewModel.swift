import Foundation
import InsightCore
import Observation

/// Writes synthetic data into the health store. Debug builds only; the view
/// model sees just this protocol, never the platform store.
public protocol SampleDataSeeding: Sendable {
    var scenarios: [SampleScenario] { get }
    func seed(_ scenario: SampleScenario) async throws
    func clear() async throws
}

public struct SampleScenario: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

/// One selectable model backend, supplied by the composition root.
public struct AssistantOption: Sendable, Identifiable {
    public let id: String
    public let title: String
    public let makeClient: @Sendable () -> any InsightModelClient

    public init(id: String, title: String, makeClient: @escaping @Sendable () -> any InsightModelClient) {
        self.id = id
        self.title = title
        self.makeClient = makeClient
    }
}

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
    public let title: String
    public let subtitle: String
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
        let access = await source.accessState()
        let now = now()
        var raw = RawHealthData.empty
        if access == .requested {
            do {
                raw = try await source.fetch(window: SnapshotBuilder.window(now: now, calendar: calendar), calendar: calendar)
            } catch {
                loadError = "Couldn't read Health data: \(error.localizedDescription)"
            }
        }
        apply(SnapshotBuilder.build(raw: raw, access: access, now: now, calendar: calendar))
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

    // MARK: - State derivation

    private func apply(_ snapshot: HealthSnapshot) {
        let insights = InsightEngine.insights(for: snapshot)
        let context = InsightContextBuilder.build(snapshot: snapshot, insights: insights)
        let format = DisplayFormatter(calendar: calendar)
        let connected = snapshot.access == .requested && loadError == nil

        header = DashboardHeader(
            title: "\(format.day(snapshot.window.start)) – \(format.day(snapshot.generatedAt)) · last 14 days + today",
            subtitle: "Averages use completed days only. Today is still in progress. Updated \(format.time(snapshot.generatedAt))."
        )
        cards = connected
            ? insights.map { MetricCardPresenter.card(for: $0, series: snapshot.series($0.metric), access: snapshot.access, calendar: calendar) }
            : []
        footnote = connected
            ? "Gray columns mean no data was recorded that day. They aren't counted as zero. Insights are for general wellness, not medical advice."
            : nil
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
