import InsightCore
import InsightPresentation
import SwiftUI

/// Renders AskViewModel state. No formatting or business rules here.
struct AskView: View {
    @Bindable var viewModel: AskViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var fieldFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label(viewModel.sourceDescription, systemImage: viewModel.isSimulated ? "testtube.2" : "sparkles")
                        .font(.caption)
                        .foregroundStyle(viewModel.isSimulated ? .orange : .secondary)
                    content
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Ask")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) { composer }
        }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.state {
        case .idle:
            VStack(alignment: .leading, spacing: 8) {
                Text("Try asking").font(.headline)
                ForEach(AskViewModel.suggestions, id: \.self) { suggestion in
                    Button {
                        Task { await viewModel.ask(suggestion: suggestion) }
                    } label: {
                        Text(suggestion)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }
            }
        case .loading(let question):
            QuestionBubble(text: question)
            HStack(spacing: 8) {
                ProgressView()
                Text("Looking at your summary…").foregroundStyle(.secondary)
            }
        case .answered(let answer):
            QuestionBubble(text: answer.question)
            AnswerView(answer: answer)
        case .failed(let question, let message, let canRetry):
            QuestionBubble(text: question)
            NoticeCard(icon: "exclamationmark.bubble", tint: .orange, title: "No answer this time", message: message) {
                if canRetry {
                    Button("Try again") { Task { await viewModel.retry() } }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask about your steps, sleep, or heart rate", text: $viewModel.draft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .submitLabel(.send)
                .onSubmit { Task { await viewModel.submit() } }
            Button {
                fieldFocused = false
                Task { await viewModel.submit() }
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title)
            }
            .disabled(!viewModel.canSubmit)
            .accessibilityLabel("Send question")
        }
        .padding()
        .background(.bar)
    }
}

private struct QuestionBubble: View {
    let text: String
    var body: some View {
        Text(text)
            .padding(12)
            .background(Color.accentColor.opacity(0.15), in: .rect(cornerRadius: 14))
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

private struct AnswerView: View {
    let answer: AnswerState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch answer.banner {
            case .needsClinician:
                NoticeCard(icon: "stethoscope", tint: .blue, title: "This is a question for a clinician",
                           message: "Rezilient can describe your trends but can't diagnose conditions or advise on treatment.")
            case .insufficientData:
                NoticeCard(icon: "chart.bar.xaxis", tint: .secondary, title: "Your data can't fully answer this",
                           message: "See the limits below for what's missing.")
            case nil:
                EmptyView()
            }

            if !answer.observations.isEmpty {
                section("From your data", icon: "chart.xyaxis.line") {
                    ForEach(answer.observations) { observation in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(observation.text)
                            HStack {
                                ForEach(observation.metrics) { metric in
                                    Label(metric.displayName, systemImage: metric.symbol)
                                        .font(.caption2)
                                        .foregroundStyle(metric.tint)
                                }
                            }
                        }
                    }
                }
            }
            if !answer.generalInfo.isEmpty {
                section("General wellness info", icon: "book", note: "Not based on your data.") {
                    ForEach(answer.generalInfo, id: \.self) { Text($0) }
                }
            }
            if !answer.limitations.isEmpty {
                section("Limits of this answer", icon: "info.circle") {
                    ForEach(answer.limitations, id: \.self) { Text($0).foregroundStyle(.secondary) }
                }
            }

            DisclosureGroup("What the assistant was given") {
                Text(answer.contextJSON)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.footnote)

            Text(answer.footer).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func section<Content: View>(_ title: String, icon: String, note: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(title, systemImage: icon).font(.headline)
                if let note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    }
}
