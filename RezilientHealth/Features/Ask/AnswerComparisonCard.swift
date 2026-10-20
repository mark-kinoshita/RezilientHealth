import SwiftUI

/// Static numerical evidence from the captured request, not model-generated text.
struct AnswerComparisonCard: View {
    let rows: [AnswerMetricRow]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider().padding(.leading, 62) }
                AnswerComparisonRow(row: row)
                    .transition(.opacity.combined(with: .offset(y: 8)))
            }
        }
        .cardBackground(cornerRadius: 18)
    }
}

private struct AnswerComparisonRow: View {
    let row: AnswerMetricRow
    @Environment(\.dynamicTypeSize) private var dynamicType

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: row.metric.symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(row.metric.tint)
                    .frame(width: 36, height: 36)
                    .background(row.metric.tint.opacity(0.09), in: .circle)
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.metric.displayName).font(.caption).foregroundStyle(.secondary)
                    Text(row.value).font(.system(.title3, design: .rounded, weight: .bold)).monospacedDigit()
                    Text(row.previous).font(.caption).foregroundStyle(.secondary)
                    if row.isStale {
                        Label("Older data", systemImage: "clock").font(.caption2).foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !dynamicType.isAccessibilitySize { comparison }
            }
            if dynamicType.isAccessibilitySize { comparison.padding(.leading, 48) }
        }
        .padding(14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.metric.displayName), average \(row.value), \(row.currentRange). \(row.previous). \(row.coverage). \(row.isStale ? "Older data." : "")")
    }

    private var comparison: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if let direction = row.direction {
                HStack(spacing: 4) {
                    Image(systemName: direction == .up ? "arrow.up" : direction == .down ? "arrow.down" : "equal")
                    if let text = row.changeText { Text(text) }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(row.metric.tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(row.metric.tint.opacity(0.08), in: .capsule)
            }
            Text(row.coverage).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
