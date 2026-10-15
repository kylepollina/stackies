// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Stackies",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Stackies", path: "Sources/Stackies")
    ]
)
