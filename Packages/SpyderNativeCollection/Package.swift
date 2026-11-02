// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SpyderNativeCollection",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "SpyderNativeCollection", targets: ["SpyderNativeCollection"])
    ],
    targets: [
        .target(
            name: "SpyderNativeCollection",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "SpyderNativeCollectionTests",
            dependencies: ["SpyderNativeCollection"]
        )
    ]
)
