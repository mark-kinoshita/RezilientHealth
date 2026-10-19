import SwiftUI

/// Neutral placeholders occupy the dashboard layout until the first read settles.
/// They contain no example health values or implied insights.
struct DashboardLoadingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                ProgressView().tint(.blue)
                Text("Loading your health summary…")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)

            if reduceMotion {
                placeholders.opacity(0.6)
            } else {
                PhaseAnimator([0.45, 0.8]) { opacity in
                    placeholders.opacity(opacity)
                } animation: { _ in .easeInOut(duration: 1) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading your health summary from Apple Health")
    }

    private var placeholders: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                RoundedRectangle(cornerRadius: 4).frame(width: 180, height: 18)
                RoundedRectangle(cornerRadius: 4).frame(width: 230, height: 18)
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 15).frame(height: 130)
                    RoundedRectangle(cornerRadius: 15).frame(height: 130)
                }
                Capsule().frame(height: 42)
            }
            .foregroundStyle(.quaternary)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))

            VStack(spacing: 0) {
                ForEach(HealthLoadingRow.allCases) { _ in
                    HStack(spacing: 12) {
                        Circle().frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 8) {
                            RoundedRectangle(cornerRadius: 4).frame(width: 90, height: 10)
                            RoundedRectangle(cornerRadius: 4).frame(width: 125, height: 18)
                        }
                        Spacer()
                    }
                    .foregroundStyle(.quaternary)
                    .padding(14)
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
        }
        .accessibilityHidden(true)
    }
}

private enum HealthLoadingRow: CaseIterable, Identifiable {
    case first, second, third
    var id: Self { self }
}
