// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StableBar",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "StableBar", targets: ["StableBar"])],
    targets: [
        .executableTarget(name: "StableBar"),
        .testTarget(name: "StableBarTests", dependencies: ["StableBar"])
    ]
)
