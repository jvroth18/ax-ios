// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AXCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AXCore", targets: ["AXCore"])
    ],
    targets: [
        .target(name: "AXCore"),
        .testTarget(name: "AXCoreTests", dependencies: ["AXCore"]),
    ]
)
