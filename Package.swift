// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PTouchKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "PTouchKit", targets: ["PTouchKit"]),
        .executable(name: "ptsmoke", targets: ["ptsmoke"]),
    ],
    targets: [
        .target(
            name: "PTouchKit",
            linkerSettings: [
                .linkedFramework("IOBluetooth", .when(platforms: [.macOS])),
                .linkedFramework("Foundation"),
            ]
        ),
        .executableTarget(
            name: "ptsmoke",
            dependencies: ["PTouchKit"]
        ),
        .testTarget(
            name: "PTouchKitTests",
            dependencies: ["PTouchKit"]
        ),
    ]
)
