import Charts
import SwiftUI

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
