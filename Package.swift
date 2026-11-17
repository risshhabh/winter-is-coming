// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WinterIsComing",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure simulation: no AppKit, no SpriteKit. Everything here is unit-tested.
        .target(name: "WinterCore"),
        // The overlay app: window, SpriteKit renderers, window/Dock tracking, Play mode.
        .executableTarget(name: "WinterIsComing", dependencies: ["WinterCore"]),
        .testTarget(name: "WinterCoreTests", dependencies: ["WinterCore"]),
    ]
)
