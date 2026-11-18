// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DaybreakCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DaybreakCore", targets: ["DaybreakCore"]),
    ],
    targets: [
        .target(
            name: "DaybreakCore",
            resources: [.copy("Resources/things.js")]
        ),
        .testTarget(
            name: "DaybreakCoreTests",
            dependencies: ["DaybreakCore"]
        ),
    ]
)
