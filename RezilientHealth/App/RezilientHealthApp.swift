import InsightPresentation
import SwiftUI

@main
struct RezilientHealthApp: App {
    /// Composition root: the only place that knows about concrete HealthKit
    /// and model-client types. Everything below talks to protocols.
    @State private var dashboard: DashboardViewModel = {
        let source = HealthKitDataSource()
        #if DEBUG
        let seeder: (any SampleDataSeeding)? = SampleDataSeeder(store: source.store)
        #else
        let seeder: (any SampleDataSeeding)? = nil
        #endif
        return DashboardViewModel(
            source: source,
            assistantOptions: AssistantCatalog.options,
            defaultAssistantID: AssistantCatalog.defaultID,
            seeder: seeder
        )
    }()

    var body: some Scene {
        WindowGroup {
            DashboardView(viewModel: dashboard)
        }
    }
}
