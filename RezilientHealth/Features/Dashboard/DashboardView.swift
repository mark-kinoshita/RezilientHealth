import InsightCore
import InsightPresentation
import SwiftUI

/// Renders DashboardViewModel state. No formatting or business rules here.
struct DashboardView: View {
    @Bindable var viewModel: DashboardViewModel
    @State private var isAsking = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let header = viewModel.header {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(header.dateRange)
                                    .font(.headline)
                                    .contentTransition(.numericText())
                                Text(header.caption).font(.caption).foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                            Spacer()
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
                    ForEach(viewModel.cards) { card in
                        NavigationLink(value: card.metric) { MetricTile(card: card) }
                            .buttonStyle(.plain)
                    }
                    if let footnote = viewModel.footnote {
                        Text(footnote).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding()
                .animation(.default, value: viewModel.cards)
            }
            .navigationDestination(for: HealthMetric.self) { metric in
                MetricDetailView(viewModel: viewModel, metric: metric) { question in
                    viewModel.ask.draft = question
                    isAsking = true
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Summary")
            .refreshable { await viewModel.load() }
            .overlay {
                if viewModel.isLoading && viewModel.cards.isEmpty && viewModel.notices.isEmpty { ProgressView() }
            }
            .safeAreaInset(edge: .bottom) {
                Button { isAsking = true } label: {
                    Label("Ask about your data", systemImage: "sparkles").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .disabled(!viewModel.canAsk)
            }
            .toolbar {
                #if DEBUG
                ToolbarItem(placement: .topBarTrailing) { DeveloperMenu(viewModel: viewModel) }
                #endif
            }
            .sheet(isPresented: $isAsking) {
                AskView(viewModel: viewModel.ask)
            }
            .task { await viewModel.load() }
        }
    }

    private func perform(_ action: DashboardNotice.Action) {
        switch action {
        case .retry: Task { await viewModel.load() }
        case .connect: Task { await viewModel.connect() }
        case .openSettings:
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
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
private struct DeveloperMenu: View {
    @Bindable var viewModel: DashboardViewModel

    var body: some View {
        Menu {
            Section("Sample data (writes to Health)") {
                ForEach(viewModel.sampleScenarios) { scenario in
                    Button(scenario.title) { Task { await viewModel.seed(scenario) } }
                }
                Button("Remove seeded data", role: .destructive) { Task { await viewModel.clearSampleData() } }
            }
            Section("Assistant backend") {
                Picker("Assistant backend", selection: $viewModel.selectedAssistantID) {
                    ForEach(viewModel.assistantOptions) { Text($0.title).tag($0.id) }
                }
            }
        } label: {
            Image(systemName: "wrench.and.screwdriver")
                .accessibilityLabel("Developer options")
        }
    }
}
#endif
