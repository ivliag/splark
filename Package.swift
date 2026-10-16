// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SplarkKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SplarkKit", targets: ["SplarkKit"]),
        .executable(name: "Splark", targets: ["Splark"]),
        .executable(name: "splark-dev", targets: ["splark-dev"]),
    ],
    targets: [
        .target(name: "SplarkKit"),
        .executableTarget(name: "Splark", dependencies: ["SplarkKit"]),
        .executableTarget(name: "splark-dev", dependencies: ["SplarkKit"]),
        .testTarget(name: "SplarkKitTests", dependencies: ["SplarkKit"]),
    ]
)
