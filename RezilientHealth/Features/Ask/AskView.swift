import InsightCore
import InsightPresentation
import SwiftUI

/// Renders AskViewModel state. No formatting or business rules here.
struct AskView: View {
    @Bindable var viewModel: AskViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var fieldFocused: Bool
    @State private var showingContext = false

    private static let questionID = "question"

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        content
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.smooth(duration: 0.35), value: viewModel.state)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: viewModel.state) { _, state in
                    if case .idle = state { return }
                    withAnimation(.smooth) { proxy.scrollTo(Self.questionID, anchor: .top) }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Ask")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if showsStartOver {
                        Button("New question", systemImage: "square.and.pencil") {
                            viewModel.startOver()
                            fieldFocused = true
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
            .safeAreaBar(edge: .bottom) { composer }
        }
        .presentationDragIndicator(.visible)
        .sensoryFeedback(trigger: viewModel.state) { _, state in
            switch state {
            case .answered: .success
            case .failed: .warning
            default: nil
            }
        }
        .sheet(isPresented: $showingContext) {
            if case .answered(let answer) = viewModel.state {
                ContextSheet(json: answer.contextJSON)
            }
        }
    }

    private var showsStartOver: Bool {
        switch viewModel.state {
        case .answered, .failed: true
        case .idle, .loading: false
        }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.state {
        case .idle:
            IntroHeader(title: viewModel.introTitle, subtitle: viewModel.introSubtitle)
            SuggestionList(suggestions: viewModel.suggestions) { suggestion in
                fieldFocused = false
                Task { await viewModel.ask(suggestion: suggestion) }
            }
            SourceNote(text: viewModel.sourceDescription, isSimulated: viewModel.isSimulated)
        case .loading(let question):
            QuestionBubble(text: question).id(Self.questionID)
            ThinkingView()
                .transition(.opacity)
        case .answered(let answer):
            QuestionBubble(text: answer.question).id(Self.questionID)
            AnswerView(answer: answer) { showingContext = true }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        case .failed(let question, let message, let canRetry):
            QuestionBubble(text: question).id(Self.questionID)
            Callout(icon: "exclamationmark.triangle.fill", tint: .orange, title: "No answer this time", message: message) {
                if canRetry {
                    Button("Try again", systemImage: "arrow.clockwise") {
                        Task { await viewModel.retry() }
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.orange)
                    .padding(.top, 4)
                }
            }
            .transition(.opacity)
        }
    }

    /// Field and send button share a glass container so they read as one
    /// control and blend where they meet.
    private var composer: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask about your data", text: $viewModel.draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($fieldFocused)
                    .submitLabel(.send)
                    .onSubmit { Task { await viewModel.submit() } }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 13)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
                Button {
                    fieldFocused = false
                    Task { await viewModel.submit() }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.bold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .disabled(!viewModel.canSubmit)
                .accessibilityLabel("Send question")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Empty state

/// The assistant's mark: the three metric colors behind a sparkle.
private struct AssistantMark: View {
    var size: CGFloat = 28

    var body: some View {
        Circle()
            .fill(AngularGradient(
                colors: [HealthMetric.steps.tint, HealthMetric.sleep.tint, HealthMetric.restingHeartRate.tint, HealthMetric.steps.tint],
                center: .center
            ))
            .overlay {
                Image(systemName: "sparkles")
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private struct IntroHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AssistantMark(size: 52)
                .padding(.bottom, 4)
            Text(title)
                .font(.title2.bold())
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }
}

private struct SuggestionList: View {
    let suggestions: [String]
    let select: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title: "Suggestions")
            VStack(spacing: 0) {
                ForEach(Array(suggestions.enumerated()), id: \.element) { index, suggestion in
                    if index > 0 { Divider().padding(.leading, 16) }
                    Button { select(suggestion) } label: {
                        HStack(spacing: 12) {
                            Text(suggestion)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "arrow.up.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .cardBackground()
        }
    }
}

private struct SourceNote: View {
    let text: String
    let isSimulated: Bool

    var body: some View {
        Label(text, systemImage: isSimulated ? "testtube.2" : "lock.shield")
            .font(.footnote)
            .foregroundStyle(isSimulated ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
    }
}

// MARK: - Conversation

private struct QuestionBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(Color.accentColor, in: UnevenRoundedRectangle(
                topLeadingRadius: 20, bottomLeadingRadius: 20, bottomTrailingRadius: 6, topTrailingRadius: 20
            ))
            .padding(.leading, 48)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

private struct ThinkingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                AssistantMark()
                    .symbolEffect(.breathe)
                Text("Reading your summary…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            PhaseAnimator([0.35, 0.8]) { opacity in
                VStack(alignment: .leading, spacing: 10) {
                    ForEach([1.0, 0.92, 0.6], id: \.self) { fraction in
                        GeometryReader { geometry in
                            Capsule()
                                .fill(.fill.secondary)
                                .frame(width: geometry.size.width * fraction)
                        }
                        .frame(height: 12)
                    }
                }
                .opacity(opacity)
            } animation: { _ in .easeInOut(duration: 0.9) }
            .padding(16)
            .cardBackground()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reading your summary")
    }
}

private struct AnswerView: View {
    let answer: AnswerState
    let showContext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                AssistantMark()
                Text("Rezilient").font(.subheadline.weight(.semibold))
                if answer.isSimulated {
                    Text("Simulated")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.orange.opacity(0.15), in: .capsule)
                }
            }

            switch answer.banner {
            case .needsClinician:
                Callout(icon: "stethoscope", tint: .blue, title: "This is a question for a clinician",
                        message: "Rezilient can describe your trends but can't diagnose conditions or advise on treatment.")
            case .insufficientData:
                Callout(icon: "chart.bar.xaxis", tint: .gray, title: "Your data can't fully answer this",
                        message: "See the limits below for what's missing.")
            case nil:
                EmptyView()
            }

            if !answer.observations.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(title: "From your data")
                    RowCard(rows: answer.observations.map { observation in
                        .init(id: observation.id, text: observation.text, badge: observation.metrics.first.map(Badge.metric) ?? .generic,
                              accessibilityPrefix: observation.metrics.map(\.displayName).joined(separator: ", "))
                    })
                }
            }

            if !answer.generalInfo.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(title: "General wellness info", note: "Not based on your data")
                    RowCard(rows: answer.generalInfo.enumerated().map { index, text in
                        .init(id: index, text: text, badge: .general, accessibilityPrefix: "General information")
                    })
                }
            }

            if !answer.limitations.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(title: "Limits of this answer")
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(answer.limitations, id: \.self) { limitation in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("•")
                                Text(limitation)
                            }
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Button("What the assistant saw", systemImage: "doc.text.magnifyingglass", action: showContext)
                    .font(.footnote.weight(.medium))
                Text(answer.footer)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 2)
        }
    }
}

// MARK: - Building blocks

private enum Badge {
    case metric(HealthMetric)
    case general
    case generic

    var symbol: String {
        switch self {
        case .metric(let metric): metric.symbol
        case .general: "lightbulb.fill"
        case .generic: "chart.xyaxis.line"
        }
    }

    var tint: Color {
        switch self {
        case .metric(let metric): metric.tint
        case .general: .yellow
        case .generic: .secondary
        }
    }
}

/// One card, one row per statement, each led by a tinted icon: a metric's
/// color for data-backed observations, a neutral bulb for general info.
private struct RowCard: View {
    struct Row: Identifiable {
        let id: Int
        let text: String
        let badge: Badge
        let accessibilityPrefix: String
    }

    let rows: [Row]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider().padding(.leading, 58) }
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: row.badge.symbol)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(row.badge.tint)
                        .frame(width: 30, height: 30)
                        .background(row.badge.tint.opacity(0.15), in: .circle)
                    Text(row.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.accessibilityPrefix). \(row.text)")
            }
        }
        .cardBackground()
    }
}

private struct SectionLabel: View {
    let title: String
    var note: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            if let note {
                Text("· \(note)")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.leading, 4)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Tinted, full-width message for banners and failures.
private struct Callout<Actions: View>: View {
    let icon: String
    let tint: Color
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(message).font(.subheadline).foregroundStyle(.secondary)
                actions
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(tint.opacity(0.12), in: .rect(cornerRadius: 16))
    }
}

extension Callout where Actions == EmptyView {
    init(icon: String, tint: Color, title: String, message: String) {
        self.init(icon: icon, tint: tint, title: title, message: message) { EmptyView() }
    }
}

private struct ContextSheet: View {
    let json: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Along with your question and the app's instructions, this summary is everything the assistant received.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(json)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardBackground()
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("What the assistant saw")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
