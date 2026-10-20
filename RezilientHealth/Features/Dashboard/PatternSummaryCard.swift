import SwiftUI

/// A quick, visual summary of the strongest fresh changes; detail remains below.
struct PatternSummaryCard: View {
    let summary: PatternSummaryState
    let explore: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize || summary.evidence.count == 1
            ? [GridItem(.flexible())]
            : [GridItem(.adaptive(minimum: 145), spacing: 10)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(summary.evidence.count > 1 ? summary.title.replacingOccurrences(of: ". ", with: ".\n") : summary.title)
                .font(.system(.title3, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            if summary.evidence.isEmpty, let title = summary.supportingTitle, let text = summary.supportingText {
                Label("\(title): \(text)", systemImage: HealthMetric.sleep.symbol)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(HealthMetric.sleep.tint)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !summary.evidence.isEmpty {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    ForEach(summary.evidence) { evidence in
                        ComparisonCard(evidence: evidence)
                    }
                }
            }

            Label(summary.explanation, systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 2)

            Button(action: explore) {
                HStack(spacing: 8) {
                    Text("Explore this pattern")
                    Image(systemName: "chevron.right").font(.caption.weight(.bold))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(LinearGradient(colors: [.blue, Color(red: 0.08, green: 0.6, blue: 1)], startPoint: .leading, endPoint: .trailing), in: .capsule)
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens Ask with a question about this summary. Review it before sending.")

        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 20)
                    .fill(colorScheme == .dark ? Color(.secondarySystemGroupedBackground) : Color(red: 1.0, green: 0.995, blue: 0.985))
            }
            .clipShape(.rect(cornerRadius: 20))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(.primary.opacity(0.035), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }
}

private struct ComparisonCard: View {
    let evidence: PatternSummaryState.Evidence
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var valueLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 5))
            : AnyLayout(HStackLayout(spacing: 5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: evidence.metric.symbol)
                    .font(.subheadline)
                    .foregroundStyle(evidence.metric.tint)
                    .frame(width: 30, height: 30)
                    .background(evidence.metric.tint.opacity(0.09), in: .circle)
                Text(evidence.metric.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            valueLayout {
                Text(evidence.previousValue)
                    .foregroundStyle(.secondary)
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                Text(evidence.currentValue)
                    .foregroundStyle(.primary)
            }
            .font(.system(.subheadline, weight: .medium))
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(evidence.metric.displayName): \(evidence.previousValue) in \(evidence.previousRange), \(evidence.currentValue) in \(evidence.currentRange)")

            Text(evidence.changeText)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(evidence.metric.tint)
                .fixedSize(horizontal: false, vertical: true)

            DailyBars(evidence: evidence)
                .frame(height: 34)
                .accessibilityHidden(true)

            Text(evidence.coverageShort)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 15))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(evidence.metric.displayName). \(evidence.text). \(evidence.coverageShort).")
    }
}


private struct DailyBars: View {
    let evidence: PatternSummaryState.Evidence

    private var lastRecordedDay: Date? { evidence.dailyValues.last(where: { $0.value != nil })?.day }

    private var domain: ClosedRange<Double> {
        let values = evidence.dailyValues.compactMap(\.value)
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        if evidence.metric == .restingHeartRate { return (low - 8)...(high + 8) }
        return 0...max(high, 1)
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(evidence.dailyValues) { sample in
                    let height: CGFloat = {
                        guard let value = sample.value else { return 3 }
                        let span = max(domain.upperBound - domain.lowerBound, 1)
                        return max(4, geometry.size.height * CGFloat((value - domain.lowerBound) / span))
                    }()
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(sample.value == nil ? Color.secondary.opacity(0.16) : evidence.metric.tint.opacity(sample.day == lastRecordedDay ? 1 : 0.24))
                        .frame(maxWidth: .infinity)
                        .frame(height: min(height, geometry.size.height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}
