// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CueX",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CueX", targets: ["CueX"])
    ],
    targets: [
        .executableTarget(name: "CueX"),
        .testTarget(name: "CueXTests", dependencies: ["CueX"])
    ]
)
