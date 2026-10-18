// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Kornflake",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Kornflake", targets: ["Kornflake"]),
        .library(name: "KornflakeCore", targets: ["KornflakeCore"]),
    ],
    targets: [
        .target(name: "KornflakeCore"),
        .executableTarget(name: "Kornflake", dependencies: ["KornflakeCore"]),
        .testTarget(name: "KornflakeCoreTests", dependencies: ["KornflakeCore"]),
    ]
)
