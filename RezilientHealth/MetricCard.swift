import Charts
import InsightCore
import InsightPresentation
import SwiftUI

/// Renders a MetricCardState. All copy and accessibility text come from the
/// view model; this file only decides styling.
struct MetricCard: View {
    let card: MetricCardState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(card.title, systemImage: card.metric.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(card.metric.tint)
                Spacer()
                if card.isStale {
                    Text("Stale")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.orange.opacity(0.2), in: .capsule)
                        .foregroundStyle(.orange)
                }
            }
            Text(card.headline)
                .font(.title3.weight(.semibold))
                .foregroundStyle(card.isHeadlineMuted ? .secondary : .primary)
            if !card.chart.isEmpty {
                MetricChart(card: card).frame(height: 140)
            }
            Text(card.detail).font(.subheadline)
            if let coverage = card.coverageNote {
                Text(coverage).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .contain)
    }
}

private struct MetricChart: View {
    let card: MetricCardState

    var body: some View {
        Chart {
            ForEach(card.chart) { point in
                if let value = point.value {
                    valueMark(point, value: value)
                } else {
                    // Explicit "no data" column so a gap never reads as a low day.
                    RectangleMark(x: .value("Day", point.day, unit: .day))
                        .foregroundStyle(.gray.opacity(0.15))
                        .accessibilityLabel(point.accessibilityLabel)
                        .accessibilityValue(point.accessibilityValue)
                }
            }
            if let target = card.targetLine {
                RuleMark(y: .value("Target", target))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.secondary)
                    .annotation(position: .top, alignment: .leading) {
                        Text("\(Int(target))h").font(.caption2).foregroundStyle(.secondary)
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                AxisValueLabel(format: .dateTime.day(), centered: true)
            }
        }
        .chartYScale(domain: .automatic(includesZero: card.chartIncludesZero))
    }

    @ChartContentBuilder
    private func valueMark(_ point: MetricCardState.ChartPoint, value: Double) -> some ChartContent {
        let style = card.metric.tint.opacity(point.isPartial ? 0.35 : 1)
        if card.metric == .restingHeartRate {
            PointMark(x: .value("Day", point.day, unit: .day), y: .value(card.metric.unit, value))
                .foregroundStyle(style)
                .accessibilityLabel(point.accessibilityLabel)
                .accessibilityValue(point.accessibilityValue)
        } else {
            BarMark(x: .value("Day", point.day, unit: .day), y: .value(card.metric.unit, value))
                .foregroundStyle(style)
                .accessibilityLabel(point.accessibilityLabel)
                .accessibilityValue(point.accessibilityValue)
        }
    }
}

/// Visual identity per metric (styling only).
extension HealthMetric {
    var symbol: String {
        switch self {
        case .steps: "figure.walk"
        case .sleep: "bed.double.fill"
        case .restingHeartRate: "heart.fill"
        }
    }

    var tint: Color {
        switch self {
        case .steps: .green
        case .sleep: .indigo
        case .restingHeartRate: .pink
        }
    }
}
