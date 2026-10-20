import Foundation
import Observation

/// Writes synthetic data into the health store. Debug builds only; the view
/// model sees just this protocol, never the platform store.
public protocol SampleDataSeeding: Sendable {
    var scenarios: [SampleScenario] { get }
    func seed(_ scenario: SampleScenario) async throws
    func clear() async throws
}

public struct SampleScenario: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

/// One selectable model backend, supplied by the composition root.
public struct AssistantOption: Sendable, Identifiable {
    public let id: String
    public let title: String
    public let makeClient: @Sendable () -> any InsightModelClient
    public let unavailableReason: @Sendable () -> String?
    public let isDiagnostic: Bool

    public init(id: String, title: String, isDiagnostic: Bool = false, unavailableReason: @escaping @Sendable () -> String? = { nil }, makeClient: @escaping @Sendable () -> any InsightModelClient) {
        self.id = id
        self.title = title
        self.makeClient = makeClient
        self.unavailableReason = unavailableReason
        self.isDiagnostic = isDiagnostic
    }
}
