// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AXCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AXCore", targets: ["AXCore"]),
        // Mac-side eval driver. The app links the library product only, so this target
        // never ends up in the iOS build.
        .executable(name: "ax-eval", targets: ["ax-eval"]),
    ],
    targets: [
        .target(name: "AXCore"),
        .executableTarget(name: "ax-eval", dependencies: ["AXCore"]),
        .testTarget(name: "AXCoreTests", dependencies: ["AXCore"]),
    ]
)
