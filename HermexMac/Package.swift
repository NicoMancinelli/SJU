// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Hermex",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Hermex",
            path: "Sources/Hermex"
        ),
        .testTarget(
            name: "HermexTests",
            dependencies: ["Hermex"],
            path: "Tests/HermexTests"
        )
    ]
)
