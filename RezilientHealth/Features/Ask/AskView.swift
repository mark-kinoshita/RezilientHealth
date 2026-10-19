import InsightCore
import InsightPresentation
import SwiftUI

/// Renders AskViewModel state. No formatting or business rules here.
struct AskView: View {
    @Bindable var viewModel: AskViewModel
    let assistantOptions: [AssistantOption]
    @Binding var selectedAssistantID: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var fieldFocused: Bool
    @State private var showingContext = false
    @State private var followsLatest = true
    @State private var isNearBottom = true
    @State private var isUserScrolling = false
    @State private var scrollRequest = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let questionID = "question"
    private static let bottomID = "latest-content"

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        content
                        Color.clear.frame(height: 1).id(Self.bottomID)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollDismissesKeyboard(.interactively)
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentSize.height + geometry.contentInsets.bottom
                        - geometry.contentOffset.y - geometry.containerSize.height < 80
                } action: { _, nearBottom in
                    isNearBottom = nearBottom
                    if isUserScrolling { followsLatest = nearBottom }
                }
                .onScrollPhaseChange { _, phase in
                    switch phase {
                    case .tracking, .interacting, .decelerating:
                        isUserScrolling = true
                    case .idle:
                        let wasUserScrolling = isUserScrolling
                        isUserScrolling = false
                        if wasUserScrolling { followsLatest = isNearBottom }
                    case .animating:
                        isUserScrolling = false
                    @unknown default:
                        break
                    }
                }
                .onChange(of: viewModel.state) { _, state in
                    switch state {
                    case .idle:
                        followsLatest = true
                    case .loading:
                        followsLatest = true
                        scrollRequest += 1
                    case .answered, .failed:
                        scrollRequest += 1
                    }
                }
                .onScrollGeometryChange(for: CGFloat.self) { $0.containerSize.height } action: { _, _ in
                    if !isIdle { scrollRequest += 1 }
                }
                .task(id: scrollRequest) {
                    // Allow the newly inserted answer rows to participate in layout.
                    await Task.yield()
                    guard !Task.isCancelled, followsLatest, !isUserScrolling, !isIdle else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                        proxy.scrollTo(Self.bottomID, anchor: .bottom)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if !followsLatest && !isIdle {
                        Button {
                            followsLatest = true
                            scrollRequest += 1
                        } label: {
                            Label("Latest", systemImage: "arrow.down")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(.regularMaterial, in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .padding(12)
                        .accessibilityLabel("Scroll to latest content")
                    }
                }
            }
            .background(colorScheme == .dark ? Color(.systemGroupedBackground) : Color(red: 0.99, green: 0.985, blue: 0.975))
            .navigationTitle("Ask")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Assistant model", selection: $selectedAssistantID) {
                            ForEach(assistantOptions) { option in
                                let reason = option.unavailableReason()
                                Text(reason.map { "\(option.title) — \($0)" } ?? option.title)
                                    .tag(option.id)
                                    .disabled(reason != nil)
                            }
                        }
                    } label: {
                        Label("Choose assistant model", systemImage: "cpu")
                            .labelStyle(.iconOnly)
                    }
                    .accessibilityLabel("Choose assistant model")
                    .accessibilityValue(assistantOptions.first { $0.id == selectedAssistantID }?.title ?? "")
                }
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
                ContextSheet(json: answer.modelInput)
            }
        }
    }

    private var isIdle: Bool {
        if case .idle = viewModel.state { true } else { false }
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
            AnswerView(answer: answer, onReveal: { scrollRequest += 1 }, askFollowUp: { question in
                fieldFocused = false
                Task { await viewModel.ask(suggestion: question) }
            }) { showingContext = true }
        case .failed(let question, let message, let canRetry):
            QuestionBubble(text: question).id(Self.questionID)
            AskCallout(icon: "exclamationmark.triangle.fill", tint: .orange, title: "No answer this time", message: message) {
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

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(isIdle ? "Ask about your data" : "Ask a follow-up…", text: $viewModel.draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($fieldFocused)
                .submitLabel(.send)
                .onSubmit { Task { await viewModel.submit() } }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 24))
                .overlay {
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(.blue.opacity(fieldFocused ? 0.3 : 0.09), lineWidth: 1)
                }
            Button {
                fieldFocused = false
                Task { await viewModel.submit() }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(.blue.opacity(viewModel.canSubmit ? 1 : 0.25), in: .circle)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canSubmit)
            .accessibilityLabel("Send question")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

}
