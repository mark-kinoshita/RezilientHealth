import InsightCore
import InsightPresentation
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
/// The illustration is built from native symbols and shapes so it scales with
/// Dynamic Type and does not add a raster asset to the dashboard bundle.
struct ConnectHealthEmptyState: View {
    let connect: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            HealthConnectionArtwork()
                .frame(maxWidth: 300)
                .frame(height: 226)
                .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text("Your health story starts here")
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)

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
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .clipShape(Capsule())
            .frame(maxWidth: 340)

            Label("Your raw health data stays on this device.", systemImage: "lock.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.top, 34)
        .padding(.bottom, 26)
    }
}

private struct HealthConnectionArtwork: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [.mint, .blue.opacity(0.7), .indigo.opacity(0.55), .mint],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 18, lineCap: .round)
                )
                .frame(width: 202, height: 202)
                .rotationEffect(.degrees(-35))
                .blur(radius: 0.2)

            Circle()
                .fill(.white.opacity(0.58))
                .frame(width: 106, height: 106)
                .overlay {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(colors: [.pink, .red], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                }
                .shadow(color: .pink.opacity(0.15), radius: 18, y: 8)

            connectionBadge("figure.walk", tint: .mint, angle: -142)
            connectionBadge("bed.double.fill", tint: .indigo, angle: -38)
            connectionBadge("sparkles", tint: .blue, angle: 48)
        }
        .frame(width: 250, height: 220)
    }

    private func connectionBadge(_ symbol: String, tint: Color, angle: Double) -> some View {
        Circle()
            .fill(tint.opacity(0.13))
            .frame(width: 70, height: 70)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .offset(x: 90 * cos(angle * .pi / 180), y: 90 * sin(angle * .pi / 180))
    }
}
