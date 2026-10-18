import InsightCore
import SwiftUI

/// Compact time-range control: a small glass pill ("Week ⌃⌄") that opens a
/// menu. Takes far less room than a segmented control and sits beside the
/// date range it changes.
struct RangeMenu: View {
    let selection: TimeRange
    let onSelect: (TimeRange) -> Void

    var body: some View {
        Menu {
            Picker("Time range", selection: Binding(get: { selection }, set: onSelect)) {
                ForEach(TimeRange.allCases) { range in
                    Text(range.menuTitle).tag(range)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selection.title)
                    .contentTransition(.interpolate)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.glass)
        .controlSize(.small)
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityLabel("Time range")
        .accessibilityValue(selection.title)
    }
}

private extension TimeRange {
    var menuTitle: String {
        switch self {
        case .week: "Week · 7 days"
        case .month: "Month · 30 days"
        case .quarter: "3 Months · 90 days"
        }
    }
}
