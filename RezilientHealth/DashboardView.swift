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
                VStack(alignment: .leading, spacing: 16) {
                    if let header = viewModel.header {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(header.title).font(.subheadline.weight(.semibold))
                            Text(header.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
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
                    ForEach(viewModel.cards) { MetricCard(card: $0) }
                    if let footnote = viewModel.footnote {
                        Text(footnote).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Your week")
            .refreshable { await viewModel.load() }
            .overlay {
                if viewModel.isLoading && viewModel.header == nil { ProgressView() }
            }
            .safeAreaInset(edge: .bottom) {
                Button { isAsking = true } label: {
                    Label("Ask about your data", systemImage: "sparkles").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
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

struct NoticeCard<Actions: View>: View {
    let icon: String
    let tint: Color
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(tint)
            Text(message)
                .font(.subheadline)
            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    }
}

extension NoticeCard where Actions == EmptyView {
    init(icon: String, tint: Color, title: String, message: String) {
        self.init(icon: icon, tint: tint, title: title, message: message) { EmptyView() }
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
