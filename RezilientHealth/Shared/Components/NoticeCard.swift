import SwiftUI

struct NoticeCard<Actions: View>: View {
    let icon: String
    let tint: Color
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(tint)
            Text(message)
                .font(.subheadline)
            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .cardBackground()
    }
}

extension NoticeCard where Actions == EmptyView {
    init(icon: String, tint: Color, title: String, message: String) {
        self.init(icon: icon, tint: tint, title: title, message: message) { EmptyView() }
    }
}

/// A welcoming first-run state for members who have not connected Apple Health.
/// Decorative artwork stays compact while the content follows Dynamic Type.
struct ConnectHealthEmptyState: View {
    let connect: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 24) {
            if !dynamicTypeSize.isAccessibilitySize {
                HealthConnectionArtwork()
                    .accessibilityHidden(true)
            }

            VStack(spacing: 10) {
                Text("Your health story starts here")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text("Connect Apple Health to see patterns in your steps, sleep, and resting heart rate.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 340)
            }

            Button(action: connect) {
                Label("Connect Apple Health", systemImage: "heart.text.square.fill")
                    .font(.body.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .buttonBorderShape(.capsule)
            .frame(maxWidth: 340)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "lock.fill")
                    .accessibilityHidden(true)
                Text("Your raw health data stays on this device.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 300)
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: 380)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
        .padding(.bottom, 26)
    }
}

private struct HealthConnectionArtwork: View {
    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    AngularGradient(
                        colors: [.mint.opacity(0.5), .blue.opacity(0.45), .indigo.opacity(0.3), .mint.opacity(0.5)],
                        center: .center
                    ),
                    lineWidth: 7
                )
                .frame(width: 148, height: 148)

            Circle()
                .fill(.pink.opacity(0.06))
                .frame(width: 104, height: 104)
                .overlay {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(.pink)
                }

            connectionBadge("figure.walk", tint: .teal, angle: -145)
            connectionBadge("bed.double.fill", tint: .indigo, angle: -35)
            connectionBadge("sparkles", tint: .blue, angle: 55)
        }
        .frame(width: 244, height: 224)
    }

    private func connectionBadge(_ symbol: String, tint: Color, angle: Double) -> some View {
        Circle()
            .fill(.background)
            .overlay {
                Circle().fill(tint.opacity(0.09))
            }
            .overlay {
                Circle().strokeBorder(tint.opacity(0.12), lineWidth: 1)
            }
            .frame(width: 48, height: 48)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(tint)
            }
            .offset(x: 102 * cos(angle * .pi / 180), y: 102 * sin(angle * .pi / 180))
    }
}
