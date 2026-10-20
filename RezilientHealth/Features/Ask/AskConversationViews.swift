import SwiftUI

// MARK: - Empty state

/// A small blue mark for the assistant in conversation states.
struct AssistantMark: View {
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: "sparkle.magnifyingglass")
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(.blue)
            .frame(width: size, height: size)
            .background(.blue.opacity(0.09), in: .circle)
            .accessibilityHidden(true)
    }
}

struct SuggestionList: View {
    let suggestions: [String]
    let select: (String) -> Void

    private func style(for index: Int) -> (symbol: String, tint: Color) {
        switch index {
        case 0: ("sparkle.magnifyingglass", .blue)
        case 1: (HealthMetric.steps.symbol, HealthMetric.steps.tint)
        case 2: (HealthMetric.restingHeartRate.symbol, HealthMetric.restingHeartRate.tint)
        case 3: ("stethoscope", HealthMetric.sleep.tint)
        default: ("questionmark", .orange)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Try a question")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(suggestions.enumerated()), id: \.element) { index, suggestion in
                    let appearance = style(for: index)
                    if index > 0 { Divider().padding(.leading, 60) }
                    Button { select(suggestion) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: appearance.symbol)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(appearance.tint)
                                .frame(width: 34, height: 34)
                                .background(appearance.tint.opacity(0.09), in: .circle)
                                .accessibilityHidden(true)
                            Text(suggestion)
                                .font(.subheadline.weight(.medium))
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .cardBackground(cornerRadius: 18)
        }
    }
}

struct SourceNote: View {
    let text: String
    let isSimulated: Bool

    var body: some View {
        Label(text, systemImage: isSimulated ? "testtube.2" : "lock.shield")
            .font(.caption)
            .foregroundStyle(isSimulated ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 4)
    }
}

// MARK: - Conversation

struct QuestionBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(LinearGradient(colors: [.blue, Color(red: 0.08, green: 0.6, blue: 1)], startPoint: .leading, endPoint: .trailing), in: UnevenRoundedRectangle(
                topLeadingRadius: 20, bottomLeadingRadius: 20, bottomTrailingRadius: 6, topTrailingRadius: 20
            ))
            .padding(.leading, 48)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct ThinkingView: View {
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

struct AnswerView: View {
    let answer: AnswerState
    let onReveal: () -> Void
    let askFollowUp: (String) -> Void
    let showContext: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var visibleItems = 0
    @State private var notesExpanded = false

    private var generalCount: Int { min(max(0, visibleItems - 1), answer.generalInfo.count) }
    private var metricStart: Int { 1 + answer.generalInfo.count }
    private var metricCount: Int { min(max(0, visibleItems - metricStart), answer.metricRows.count) }
    private var observationStart: Int { metricStart + answer.metricRows.count }
    private var observationCount: Int { min(max(0, visibleItems - observationStart), answer.observations.count) }
    private var totalItems: Int { observationStart + answer.observations.count + 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                AssistantMark()
                Text("Rezilient").font(.subheadline.weight(.semibold))
                if answer.isSimulated {
                    Text("Simulated")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.orange.opacity(0.1), in: .capsule)
                }
            }

            switch answer.banner {
            case .needsClinician:
                AskCallout(icon: "stethoscope", tint: .blue, title: "This is a question for a clinician",
                        message: "Rezilient can describe your trends but can't diagnose conditions or advise on treatment.")
            case .insufficientData:
                AskCallout(icon: "chart.bar.xaxis", tint: .gray, title: "Your data can't fully answer this",
                        message: "See the data notes for what's missing.")
            case nil:
                EmptyView()
            }

            if visibleItems > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    Text(answer.takeaway)
                        .font(.title3.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                }
                .transition(.opacity)
            }

            if generalCount > 0 {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.orange)
                        .frame(width: 34, height: 34)
                        .background(.yellow.opacity(0.09), in: .circle)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("General guidance").font(.subheadline.weight(.semibold))
                        Text("Not a personal assessment").font(.caption2).foregroundStyle(.secondary)
                        ForEach(answer.generalInfo.prefix(generalCount), id: \.self) { text in
                            Text(text)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .transition(.opacity)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardBackground(cornerRadius: 18)
            }

            if metricCount > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    if let period = answer.periodLabel {
                        Text(period).font(.caption).foregroundStyle(.secondary)
                    }
                    Text("From your data · recorded-day averages")
                        .font(.caption).foregroundStyle(.secondary)
                    AnswerComparisonCard(rows: Array(answer.metricRows.prefix(metricCount)))
                }
            }

            ForEach(answer.observations.prefix(observationCount)) { observation in
                Text(observation.text)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("From your data. \(observation.text)")
                    .transition(.opacity.combined(with: .offset(y: 8)))
            }

            if visibleItems >= totalItems {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 12) {
                        if !answer.dataNotes.isEmpty {
                            DisclosureGroup("Data notes · \(answer.dataNotes.count)", isExpanded: $notesExpanded) {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(answer.dataNotes, id: \.self) { note in
                                        Text(note).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.top, 8)
                            }
                            .font(.subheadline)
                            Divider()
                        }
                        Button("What the assistant saw", systemImage: "doc.text.magnifyingglass", action: showContext)
                            .font(.subheadline)
                    }
                    .padding(14)
                    .cardBackground(cornerRadius: 18)

                    if !answer.followUps.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(answer.followUps) { followUp in
                                    Button { askFollowUp(followUp.question) } label: {
                                        Label(followUp.title, systemImage: followUp.metric.symbol)
                                            .font(.caption.weight(.medium))
                                            .padding(.horizontal, 12).frame(minHeight: 44)
                                            .background(.blue.opacity(0.07), in: .capsule)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                    Text(answer.footer).font(.caption2).foregroundStyle(.secondary)
                }
                .transition(.opacity)
            }
        }
        .onChange(of: notesExpanded) { _, _ in onReveal() }
        .task(id: answer) {
            // Only complete validated answers are revealed; numeric evidence is local.
            visibleItems = 0
            notesExpanded = answer.banner != nil
            if reduceMotion || voiceOverEnabled || answer.banner != nil {
                visibleItems = totalItems
                onReveal()
                return
            }
            for count in 1...totalItems {
                do { try await Task.sleep(for: .milliseconds(count == 1 ? 100 : 360)) }
                catch { return }
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.25)) { visibleItems = count }
                onReveal()
            }
        }
    }
}

/// Tinted, full-width message for banners and failures.
struct AskCallout<Actions: View>: View {
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
        .background(tint.opacity(0.07), in: .rect(cornerRadius: 18))
    }
}

extension AskCallout where Actions == EmptyView {
    init(icon: String, tint: Color, title: String, message: String) {
        self.init(icon: icon, tint: tint, title: title, message: message) { EmptyView() }
    }
}

struct ContextSheet: View {
    let json: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("The app's instructions, health snapshot, recent conversation, and question used for this answer. Built-in safety messages do not call the model.")
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
