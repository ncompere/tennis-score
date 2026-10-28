// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TennisCore",
    platforms: [.macOS(.v13), .watchOS(.v10)],
    products: [.library(name: "TennisCore", targets: ["TennisCore"])],
    targets: [
        .target(name: "TennisCore"),
        .testTarget(name: "TennisCoreTests", dependencies: ["TennisCore"])
    ]
)
