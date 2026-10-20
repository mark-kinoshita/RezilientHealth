import Charts
import SwiftUI

/// Dense dashboard row; tapping it opens the existing full metric detail.
struct WeeklyMetricRow: View {
    let card: MetricCardState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: card.metric.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(card.metric.tint)
                .frame(width: 40, height: 40)
                .background(card.metric.tint.opacity(0.11), in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(card.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(card.statusLine ?? card.value + (card.metric == .restingHeartRate ? " bpm" : ""))
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                if card.statusLine == nil, card.metric == .steps {
                    Text(card.unit).font(.caption2).foregroundStyle(.secondary)
                }
                if card.isStale { StaleBadge() }
            }
            .frame(minWidth: 90, alignment: .leading)

            Spacer(minLength: 4)

            if !dynamicTypeSize.isAccessibilitySize, card.comparisonChart.contains(where: { $0.value != nil }) {
                WeeklyBars(card: card)
                    .frame(width: 78, height: 34)
                    .accessibilityHidden(true)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows details")
    }
}


private struct WeeklyBars: View {
    let card: MetricCardState

    private var points: [MetricCardState.ChartPoint] {
        card.comparisonChart
    }

    private var domain: ClosedRange<Double> {
        let values = points.compactMap(\.value)
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        if card.metric == .restingHeartRate { return (low - 8)...(high + 8) }
        return 0...max(high, 1)
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: points.count > 14 ? 0.3 : 3) {
                ForEach(points) { point in
                    let height: CGFloat = {
                        guard let value = point.value else { return 3 }
                        let span = max(domain.upperBound - domain.lowerBound, 1)
                        return max(4, geometry.size.height * CGFloat((value - domain.lowerBound) / span))
                    }()
                    Capsule(style: .continuous)
                        .fill(point.value == nil ? Color.secondary.opacity(0.16) : card.metric.tint.opacity(point.isPartial ? 0.45 : 0.9))
                        .frame(maxWidth: .infinity)
                        .frame(height: min(height, geometry.size.height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}
