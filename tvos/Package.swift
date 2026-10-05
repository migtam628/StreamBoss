// swift-tools-version:5.9
// Lets the platform-independent Core logic be tested anywhere with `swift test`
// (CI runs this on Linux). The tvOS app itself is built from project.yml.
import PackageDescription

let package = Package(
    name: "StreamBoss",
    platforms: [.macOS(.v13), .tvOS(.v17)],
    targets: [
        .target(name: "StreamBoss", path: "Core"),
        .testTarget(name: "StreamBossTests", dependencies: ["StreamBoss"], path: "Tests"),
    ]
)
