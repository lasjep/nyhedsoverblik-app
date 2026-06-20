// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Nyhedsoverblik",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Nyhedsoverblik",
            path: "Sources/Nyhedsoverblik",
            resources: [.copy("AppIcon.icns")]
        )
    ]
)
