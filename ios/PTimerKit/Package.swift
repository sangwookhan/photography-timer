// swift-tools-version:5.9
import PackageDescription

// PTIMER-177 / PTIMER-174 — Reusable Kit Architecture.
//
// Two-layer reusable package consumed by the PTimer host app:
//   PTimerCore — reusable, Foundation-only calculation/state engine.
//   PTimerKit  — reusable iOS app logic + SwiftUI component kit, built on Core.
//
// macOS is declared as a platform so the package test targets run
// off-simulator via `swift test` (PTIMER-174 outcome). Resources and test
// excludes are added in later commits as the engine is extracted.
let package = Package(
    name: "PTimerKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "PTimerCore", targets: ["PTimerCore"]),
        .library(name: "PTimerKit", targets: ["PTimerKit"]),
    ],
    targets: [
        .target(name: "PTimerCore"),
        .target(
            name: "PTimerKit",
            dependencies: ["PTimerCore"]
        ),
        .testTarget(
            name: "PTimerCoreTests",
            dependencies: ["PTimerCore"]
        ),
        .testTarget(
            name: "PTimerKitTests",
            dependencies: ["PTimerKit"]
        ),
    ]
)
