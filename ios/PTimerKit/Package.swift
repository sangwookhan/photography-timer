// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PTimerKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "PTimerKit", targets: ["PTimerKit"]),
    ],
    targets: [
        .target(
            name: "PTimerKit",
            resources: [
                .process("Resources/LaunchPresetFilmCatalog.json"),
            ]
        ),
        .testTarget(
            name: "PTimerKitTests",
            dependencies: ["PTimerKit"]
        ),
    ]
)
