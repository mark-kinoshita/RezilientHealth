import InsightCore
import InsightPresentation
import SwiftUI

/// One metric in depth: chart with axes, the numbers behind the tile, and the
/// explanation of coverage that the dashboard leaves out.
struct MetricDetailView: View {
    let viewModel: DashboardViewModel
    let metric: HealthMetric
    let onAsk: (String) -> Void

    private var card: MetricCardState? { viewModel.cards.first { $0.metric == metric } }

    var body: some View {
        ScrollView {
            if let card {
                VStack(alignment: .leading, spacing: 16) {

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(card.headline)
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(card.isHeadlineMuted ? .secondary : .primary)
                            if card.isStale { StaleBadge() }
                        }
                        if let delta = card.delta { DeltaChip(delta: delta) }
                    }

                    if !card.chart.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            MetricChart(card: card, style: .full)
                                .frame(height: 260)
                            HStack(spacing: 12) {
                                if let goal = card.targetLabel {
                                    Label {
                                        Text(goal)
                                    } icon: {
                                        Rectangle()
                                            .stroke(style: StrokeStyle(lineWidth: 1, dash: [1, 3]))
                                            .frame(width: 14, height: 1)
                                    }
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Label("Tap or hold to explore", systemImage: "hand.tap")
                                    .foregroundStyle(.tertiary)
                            }
                            .font(.caption2)
                        }
                        .padding()
                        .cardBackground()
                    }

                    VStack(spacing: 0) {
                        ForEach(card.stats) { stat in
                            HStack {
                                Text(stat.label).foregroundStyle(.secondary)
                                Spacer()
                                Text(stat.value).monospacedDigit()
                            }
                            .font(.subheadline)
                            .padding(.vertical, 10)
                            if stat.id != card.stats.last?.id { Divider() }
                        }
                    }
                    .padding(.horizontal)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))

                    VStack(alignment: .leading, spacing: 8) {
                        Text(card.detail)
                        if let coverage = card.coverageNote {
                            Label(coverage, systemImage: "info.circle")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if viewModel.canAsk {
                        Button {
                            onAsk("What do you notice about my \(metric.displayName.lowercased())?")
                        } label: {
                            Label("Ask about \(metric.displayName.lowercased())", systemImage: "sparkles")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                    }
                }
                .padding()
                .animation(.default, value: card)
            } else if viewModel.isLoading {
                ProgressView("Loading your health summary…")
                    .frame(maxWidth: .infinity)
                    .padding(32)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(metric.displayName)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                RangeMenu(selection: viewModel.selectedRange) { range in
                    Task { await viewModel.select(range) }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}
