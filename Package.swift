// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Agentation",
    platforms: [
        .iOS(.v16),
        // macOS is listed only so the pure model/formatting tests can run with `swift test`.
        .macOS(.v12),
    ],
    products: [
        .library(name: "Agentation", targets: ["Agentation"]),
    ],
    targets: [
        .target(name: "Agentation", path: "Sources/Agentation"),
        .testTarget(name: "AgentationTests", dependencies: ["Agentation"], path: "Tests/AgentationTests"),
    ]
)
