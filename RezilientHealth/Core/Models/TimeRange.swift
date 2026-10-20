import Foundation

/// The comparison period the member is looking at. Each range is compared
/// with the equal-length period immediately before it.
public enum TimeRange: String, CaseIterable, Codable, Sendable, Identifiable {
    case week, month, quarter

    public var id: String { rawValue }

    /// Completed days in one period (today is shown separately as partial).
    public var days: Int {
        switch self {
        case .week: 7
        case .month: 30
        case .quarter: 90
        }
    }

    /// An average needs data on at least half the period's days (4 of 7,
    /// 15 of 30, 45 of 90) before we show it or compare it.
    public var minimumDaysWithData: Int { (days + 1) / 2 }

    public var title: String {
        switch self {
        case .week: "Week"
        case .month: "Month"
        case .quarter: "3 Months"
        }
    }

    /// "this week", "the last 30 days", ...
    public var currentLabel: String {
        switch self {
        case .week: "the last 7 days"
        case .month: "the last 30 days"
        case .quarter: "the last 90 days"
        }
    }

    public var previousLabel: String {
        switch self {
        case .week: "the week before"
        case .month: "the 30 days before"
        case .quarter: "the 90 days before"
        }
    }
}
