// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WalkPadBar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "WalkPadCore"),
        .executableTarget(name: "WalkPadBar", dependencies: ["WalkPadCore"]),
        .testTarget(name: "WalkPadCoreTests", dependencies: ["WalkPadCore"]),
    ],
    swiftLanguageModes: [.v5]
)
