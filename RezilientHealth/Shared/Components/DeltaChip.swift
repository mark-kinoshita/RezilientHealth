import Charts
import SwiftUI

struct DeltaChip: View {
    let delta: MetricCardState.Delta

    var body: some View {
        Label(delta.text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color(.tertiarySystemFill), in: .capsule)
            .accessibilityLabel(delta.accessibilityText)
    }

    private var symbol: String {
        switch delta.direction {
        case .up: "arrow.up.right"
        case .down: "arrow.down.right"
        case .flat: "equal"
        }
    }
}
