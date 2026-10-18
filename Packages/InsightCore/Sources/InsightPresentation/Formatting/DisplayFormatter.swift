import Foundation
import InsightCore

/// Display formatting shared by the view models. Uses the snapshot's calendar
/// so tests are deterministic regardless of the machine's time zone.
struct DisplayFormatter {
    let calendar: Calendar

    func int(_ value: Double) -> String {
        Int(value.rounded()).formatted(.number.grouping(.automatic))
    }

    func hours(_ value: Double) -> String {
        let totalMinutes = Int((value * 60).rounded())
        return totalMinutes < 60 ? "\(totalMinutes)m" : "\(totalMinutes / 60)h \(totalMinutes % 60)m"
    }

    func day(_ date: Date) -> String {
        formatted(date, template: "MMMd")
    }

    func shortDay(_ date: Date) -> String {
        formatted(date, template: "EEEMMMd")
    }

    func longDay(_ date: Date) -> String {
        formatted(date, template: "EEEEMMMMd")
    }

    func time(_ date: Date) -> String {
        formatted(date, template: "jmm")
    }

    func range(_ stats: PeriodStats) -> String {
        guard let first = stats.firstDay, let last = stats.lastDay else { return "no days" }
        return "\(day(first))–\(day(last))"
    }

    /// The value as shown on a chart label or read by VoiceOver.
    func spoken(_ value: Double, _ metric: HealthMetric) -> String {
        switch metric {
        case .steps: "\(int(value)) steps"
        case .sleep: "\(hours(value)) asleep"
        case .restingHeartRate: "\(int(value)) beats per minute"
        }
    }

    private func formatted(_ date: Date, template: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}
