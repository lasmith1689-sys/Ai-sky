// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AiSkyKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "AiSkyKit", targets: ["AiSkyKit"]),
    ],
    targets: [
        .target(
            name: "AiSkyKit",
            path: "Sources/AiSkyKit"
        ),
        .testTarget(
            name: "AiSkyKitTests",
            dependencies: ["AiSkyKit"],
            path: "Tests/AiSkyKitTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
