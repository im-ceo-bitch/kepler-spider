// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "SpyderPayKit", platforms: [.iOS(.v17), .macOS(.v13)], products: [.library(name: "SpyderPayKit", targets: ["SpyderPayKit"])], targets: [.target(name: "SpyderPayKit"), .testTarget(name: "SpyderPayKitTests", dependencies: ["SpyderPayKit"])])
