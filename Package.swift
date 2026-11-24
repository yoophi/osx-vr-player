// swift-tools-version: 5.9
import PackageDescription

let package = Package(name: "VRPlayer", platforms: [.macOS(.v13)], targets: [
    .target(name: "PlayerCore"),
    .executableTarget(name: "VRPlayer", dependencies: ["PlayerCore"]),
    .testTarget(name: "PlayerCoreTests", dependencies: ["PlayerCore"])
])
