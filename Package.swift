// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Kornflake",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Kornflake", targets: ["Kornflake"]),
        .library(name: "KornflakeCore", targets: ["KornflakeCore"])
    ],
    targets: [
        .target(
            name: "KornflakeCore",
            path: "Sources/KornflakeCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Kornflake",
            dependencies: ["KornflakeCore"],
            path: "Sources/Kornflake",
            resources: [.copy("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "KornflakeCoreTests",
            dependencies: ["KornflakeCore"],
            path: "Tests/KornflakeCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
