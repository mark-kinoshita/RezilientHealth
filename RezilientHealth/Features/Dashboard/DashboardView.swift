import SwiftUI

/// Renders DashboardViewModel state. No formatting or business rules here.
struct DashboardView: View {
    @Bindable var viewModel: DashboardViewModel
    @State private var isAsking = false
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var headerLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center))
    }

    private var shouldShowConnectEmptyState: Bool {
        !viewModel.isInitialLoading
            && viewModel.cards.isEmpty
            && viewModel.patternSummary == nil
            && viewModel.notices.contains { $0.kind == .connect }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if viewModel.isInitialLoading {
                        DashboardLoadingView()
                    } else if shouldShowConnectEmptyState {
                        ConnectHealthEmptyState { perform(.connect) }
                    } else {
                        if let header = viewModel.header {
                            headerLayout {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(header.dateRange)
                                        .font(.headline)
                                        .contentTransition(.numericText())
                                    Text(header.caption).font(.caption).foregroundStyle(.secondary)
                                }
                                .accessibilityElement(children: .combine)
                                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                                RangeMenu(selection: viewModel.selectedRange) { range in
                                    Task { await viewModel.select(range) }
                                }
                            }
                            .animation(.snappy, value: header)
                        }
                        ForEach(viewModel.notices) { notice in
                            NoticeCard(icon: notice.kind.icon, tint: notice.kind.tint, title: notice.title, message: notice.message) {
                                if let action = notice.action, let title = notice.actionTitle {
                                    if action == .connect {
                                        Button(title) { perform(action) }.buttonStyle(.borderedProminent)
                                    } else {
                                        Button(title) { perform(action) }
                                    }
                                }
                            }
                        }
                        if let summary = viewModel.patternSummary {
                            PatternSummaryCard(summary: summary) {
                                viewModel.ask.startOver()
                                viewModel.ask.draft = summary.question
                                isAsking = true
                            }
                            Text(viewModel.periodTitle)
                                .font(.title3.weight(.semibold))
                                .accessibilityAddTraits(.isHeader)
                                .padding(.top, 8)
                        }
                        if !viewModel.cards.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(Array(viewModel.cards.enumerated()), id: \.element.id) { index, card in
                                    NavigationLink(value: card.metric) { WeeklyMetricRow(card: card) }
                                        .buttonStyle(.plain)
                                    if index < viewModel.cards.count - 1 {
                                        Divider().padding(.leading, 62)
                                    }
                                }
                            }
                            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
                        }
                        if let footnote = viewModel.footnote {
                            Text(footnote).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
                .padding(.bottom, dynamicTypeSize.isAccessibilitySize ? 0 : 12)
                .animation(.default, value: viewModel.cards)
            }
            .navigationDestination(for: HealthMetric.self) { metric in
                MetricDetailView(viewModel: viewModel, metric: metric) { question in
                    viewModel.ask.draft = question
                    isAsking = true
                }
            }
            .background(colorScheme == .dark ? Color(.systemGroupedBackground) : Color(red: 0.99, green: 0.985, blue: 0.975))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await viewModel.load() }
            .safeAreaInset(edge: .bottom) {
                if !viewModel.isInitialLoading && !shouldShowConnectEmptyState {
                    if dynamicTypeSize.isAccessibilitySize {
                        Button { isAsking = true } label: {
                            Label("Ask", systemImage: "bubble.left.fill")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(!viewModel.canAsk)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.bar)
                        .accessibilityLabel("Ask about your data")
                    } else {
                        HStack {
                            Spacer()
                            Button { isAsking = true } label: {
                                Label("Ask", systemImage: "bubble.left.fill")
                                    .font(.body.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4)
                            }
                            .buttonStyle(.glassProminent)
                            .controlSize(.large)
                            .disabled(!viewModel.canAsk)
                            .accessibilityLabel("Ask about your data")
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Summary")
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityAddTraits(.isHeader)
                }
                #if DEBUG
                ToolbarItem(placement: .topBarTrailing) { DeveloperMenu(viewModel: viewModel) }
                #endif
            }
            .sheet(isPresented: $isAsking) {
                AskView(viewModel: viewModel.ask, assistantOptions: viewModel.assistantOptions.filter { !$0.isDiagnostic },
                        selectedAssistantID: $viewModel.selectedAssistantID)
            }
            .task { await viewModel.load() }
        }
    }

    private func perform(_ action: DashboardNotice.Action) {
        switch action {
        case .retry: Task { await viewModel.load() }
        case .connect: Task { await viewModel.connect() }
        case .openHealth:
            if let url = URL(string: "x-apple-health://") { openURL(url) }
        }
    }
}

private extension DashboardNotice.Kind {
    var icon: String {
        switch self {
        case .error: "exclamationmark.triangle"
        case .unavailable: "iphone.slash"
        case .connect: "heart.text.square"
        case .noVisibleData: "lock.slash"
        }
    }

    var tint: Color {
        switch self {
        case .error: .orange
        case .connect: .pink
        case .unavailable, .noVisibleData: .secondary
        }
    }
}

#if DEBUG
private struct Report: Identifiable {
    let text: String
    var id: String { text }
}

private struct DeveloperMenu: View {
    @Bindable var viewModel: DashboardViewModel
    @State private var diagnostics: String?

    var body: some View {
        Menu {
            Button("Health diagnostics", systemImage: "stethoscope") {
                Task { diagnostics = await HealthDiagnostics.report() }
            }
            Section("Sample data (writes to Health)") {
                ForEach(viewModel.sampleScenarios) { scenario in
                    Button(scenario.title) { Task { await viewModel.seed(scenario) } }
                }
                Button("Remove seeded data", role: .destructive) { Task { await viewModel.clearSampleData() } }
            }
            Section("Assistant backend") {
                Picker("Assistant backend", selection: $viewModel.selectedAssistantID) {
                    ForEach(viewModel.assistantOptions) { option in
                        let reason = option.unavailableReason()
                        Text(reason.map { "\(option.title) — \($0)" } ?? option.title)
                            .tag(option.id)
                            .disabled(reason != nil)
                    }
                }
            }
        } label: {
            Image(systemName: "wrench.and.screwdriver")
                .accessibilityLabel("Developer options")
        }
        .sheet(item: Binding(get: { diagnostics.map(Report.init) }, set: { diagnostics = $0?.text })) { report in
            NavigationStack {
                ScrollView {
                    Text(report.text)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .navigationTitle("Health diagnostics")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: report.text)
                    }
                }
            }
        }
    }
}
#endif
