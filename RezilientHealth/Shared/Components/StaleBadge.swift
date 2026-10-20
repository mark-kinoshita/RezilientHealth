import Charts
import SwiftUI

struct StaleBadge: View {
    var body: some View {
        Text("Older data")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(.orange.opacity(0.2), in: .capsule)
            .foregroundStyle(.primary)
    }
}
