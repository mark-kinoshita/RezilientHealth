import Foundation

/// A banner above the cards. The view chooses icon and color from `kind`.
public struct DashboardNotice: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable { case error, unavailable, connect, noVisibleData }
    public enum Action: Sendable, Equatable { case retry, connect, openHealth }

    public let kind: Kind
    public let title: String
    public let message: String
    public let action: Action?
    public let actionTitle: String?

    public var id: Kind { kind }
}

public struct DashboardHeader: Sendable, Equatable {
    /// "Oct 8 – Oct 14"
    public let dateRange: String
    /// "vs. Oct 1 – 7": the period the change chips measure against.
    public let caption: String
}
