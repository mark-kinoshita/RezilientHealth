// swift-tools-version: 6.0
// Platform-neutral domain logic: aggregation, insights, model contract.
// No HealthKit or SwiftUI imports, so it runs under `swift test` on macOS and
// documents the logic an Android port (Kotlin) would mirror.
import PackageDescription

let package = Package(
    name: "InsightCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "InsightCore", targets: ["InsightCore"]),
    ],
    targets: [
        .target(name: "InsightCore"),
        .testTarget(name: "InsightCoreTests", dependencies: ["InsightCore"]),
    ]
)
