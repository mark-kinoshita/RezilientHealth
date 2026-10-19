import Charts
import InsightCore
import InsightPresentation
import SwiftUI

/// Compact dashboard tile: one number, its change, a sparkline, and coverage.
/// All copy comes from the view model; this file only decides styling.
struct MetricTile: View {
    let card: MetricCardState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(card.title, systemImage: card.metric.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(card.metric.tint)
                Spacer()
                if card.isStale { StaleBadge() }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    if let status = card.statusLine {
                        Text(status)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(card.value)
                            .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text(card.unit).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if !card.chart.isEmpty {
                    MetricChart(card: card, style: .sparkline)
                        .frame(width: 130, height: 48)
                        .accessibilityHidden(true)
                }
            }

            HStack(spacing: 8) {
                if let delta = card.delta { DeltaChip(delta: delta) }
                Label(card.coverageShort, systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows details")
    }
}
