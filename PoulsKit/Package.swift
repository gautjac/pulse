// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PoulsKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "PoulsKit", targets: ["PoulsKit"])],
    targets: [
        .target(name: "PoulsKit"),
        .testTarget(name: "PoulsKitTests", dependencies: ["PoulsKit"]),
    ]
)
