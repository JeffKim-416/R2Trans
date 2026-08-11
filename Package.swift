// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "R2Trans",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "R2Trans", targets: ["R2Trans"])
    ],
    targets: [
        .executableTarget(
            name: "R2Trans",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "R2TransTests",
            dependencies: ["R2Trans"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
