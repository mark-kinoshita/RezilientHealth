// swift-tools-version: 6.0
// InsightCore: platform-neutral domain logic (aggregation, insights, model
// contract). InsightPresentation: view models and display formatting (MVVM).
// Neither imports HealthKit or SwiftUI, so both run under `swift test` on
// macOS and document the logic an Android port (Kotlin) would mirror.
import PackageDescription

let package = Package(
    name: "InsightCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "InsightCore", targets: ["InsightCore"]),
        .library(name: "InsightPresentation", targets: ["InsightPresentation"]),
    ],
    targets: [
        .target(name: "InsightCore"),
        .target(name: "InsightPresentation", dependencies: ["InsightCore"]),
        .testTarget(name: "InsightCoreTests", dependencies: ["InsightCore"]),
        .testTarget(name: "InsightPresentationTests", dependencies: ["InsightPresentation", "InsightCore"]),
    ]
)
