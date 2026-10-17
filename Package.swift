// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SpacesUltimate",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SpacesUltimate", targets: ["SpacesUltimate"])
    ],
    targets: [
        .executableTarget(
            name: "SpacesUltimate",
            path: "Sources/SpacesUltimate"
        ),
        .testTarget(
            name: "SpacesUltimateTests",
            dependencies: ["SpacesUltimate"],
            path: "Tests/SpacesUltimateTests"
        )
    ]
)
