// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SplarkKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SplarkKit", targets: ["SplarkKit"]),
        .library(name: "SplarkUI", targets: ["SplarkUI"]),
        .executable(name: "Splark", targets: ["Splark"]),
        .executable(name: "splark-dev", targets: ["splark-dev"]),
    ],
    targets: [
        .target(name: "SplarkKit"),
        .target(name: "SplarkUI", dependencies: ["SplarkKit"]),
        .executableTarget(name: "Splark", dependencies: ["SplarkKit", "SplarkUI"]),
        .executableTarget(name: "splark-dev", dependencies: ["SplarkKit", "SplarkUI"]),
        .testTarget(name: "SplarkKitTests", dependencies: ["SplarkKit"]),
        .testTarget(name: "SplarkUITests", dependencies: ["SplarkUI", "SplarkKit"]),
    ]
)
