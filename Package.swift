// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppWrapper",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "AppWrapper",
            path: "Sources/AppWrapper"
        )
    ],
    swiftLanguageModes: [.v5]
)
