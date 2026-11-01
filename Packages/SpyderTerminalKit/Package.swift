// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SpyderTerminalKit",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "SpyderTerminalKit", targets: ["SpyderTerminalKit"])],
    targets: [
        .target(name: "SpyderTerminalKit", resources: [.process("Resources")]),
        .testTarget(name: "SpyderTerminalKitTests", dependencies: ["SpyderTerminalKit"])
    ]
)
