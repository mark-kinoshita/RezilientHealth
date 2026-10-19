import Foundation
import InsightCore
import Testing
@testable import InsightPresentation

final class FakeSource: HealthDataSource, @unchecked Sendable {
    var access: HealthAccessState
    var raw = RawHealthData.empty
    var fetchError: Error?
    private(set) var fetchedWindows: [DateInterval] = []

    init(access: HealthAccessState) { self.access = access }

    func accessState() async -> HealthAccessState { access }
    func requestAccess() async throws { access = .requested }
    func fetch(window: DateInterval, calendar: Calendar) async throws -> RawHealthData {
        fetchedWindows.append(window)
        if let fetchError { throw fetchError }
        return raw
    }
}

/// Deliberately ignores cancellation so tests verify obsolete replies are discarded.
actor SuspendedModelClient: InsightModelClient {
    nonisolated var sourceLabel: String { "Suspended test client" }
    nonisolated var isSimulated: Bool { true }
    private var requests: [ModelRequest] = []
    private var pending: [Int: CheckedContinuation<String, Never>] = [:]
    private var waiting: [Int: CheckedContinuation<Void, Never>] = [:]

    func complete(_ request: ModelRequest) async throws(ModelError) -> String {
        requests.append(request)
        let id = requests.count
        return await withCheckedContinuation { continuation in
            pending[id] = continuation
            waiting.removeValue(forKey: id)?.resume()
        }
    }

    func waitForCall(_ id: Int) async {
        if pending[id] != nil { return }
        await withCheckedContinuation { waiting[id] = $0 }
    }

    func request(_ id: Int) -> ModelRequest { requests[id - 1] }
    func finish(_ id: Int, reply: String) { pending.removeValue(forKey: id)?.resume(returning: reply) }
}

/// Each Health read can finish independently in a specified order.
actor OrderedDashboardSource: HealthDataSource {
    private var count = 0
    private var pending: [Int: CheckedContinuation<RawHealthData, any Error>] = [:]
    private var waiting: [Int: CheckedContinuation<Void, Never>] = [:]

    func accessState() async -> HealthAccessState { .requested }
    func requestAccess() async throws {}
    func fetch(window: DateInterval, calendar: Calendar) async throws -> RawHealthData {
        count += 1
        let id = count
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            waiting.removeValue(forKey: id)?.resume()
        }
    }

    func waitForFetch(_ id: Int) async {
        if pending[id] != nil { return }
        await withCheckedContinuation { waiting[id] = $0 }
    }

    func finish(_ id: Int, result: Result<RawHealthData, any Error>) {
        pending.removeValue(forKey: id)?.resume(with: result)
    }
}
