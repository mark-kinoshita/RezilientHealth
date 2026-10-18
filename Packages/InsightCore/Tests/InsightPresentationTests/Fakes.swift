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
