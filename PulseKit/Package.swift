// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PulseKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "PulseKit", targets: ["PulseKit"])],
    targets: [
        .target(name: "PulseKit"),
        .testTarget(name: "PulseKitTests", dependencies: ["PulseKit"]),
    ]
)
