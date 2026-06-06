// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PTimerCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "PTimerCore", targets: ["PTimerCore"]),
    ],
    targets: [
        .target(name: "PTimerCore"),
        .testTarget(
            name: "PTimerCoreTests",
            dependencies: ["PTimerCore"]
        ),
    ]
)
