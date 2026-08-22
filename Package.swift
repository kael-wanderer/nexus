// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Nexus",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NexusCore", targets: ["NexusCore"]),
        .library(name: "NexusUI", targets: ["NexusUI"]),
        .executable(name: "NexusApp", targets: ["NexusApp"]),
    ],
    targets: [
        .target(name: "NexusCore"),
        .target(name: "NexusUI", dependencies: ["NexusCore"]),
        .executableTarget(name: "NexusApp", dependencies: ["NexusCore", "NexusUI"]),
        .testTarget(name: "NexusCoreTests", dependencies: ["NexusCore"]),
        .testTarget(name: "NexusUITests", dependencies: ["NexusUI"]),
    ]
)
