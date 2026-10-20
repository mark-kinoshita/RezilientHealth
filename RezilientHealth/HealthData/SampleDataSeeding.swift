import Foundation

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
