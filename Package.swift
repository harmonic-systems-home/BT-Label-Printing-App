// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PTouchKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "PTouchKit", targets: ["PTouchKit"]),
        .executable(name: "ptsmoke", targets: ["ptsmoke"]),
        .executable(name: "ptprint", targets: ["ptprint"]),
    ],
    targets: [
        .target(
            name: "PTouchKit",
            resources: [
                .copy("Resources/icons"),
            ],
            linkerSettings: [
                .linkedFramework("IOBluetooth", .when(platforms: [.macOS])),
                .linkedFramework("Foundation"),
            ]
        ),
        .executableTarget(
            name: "ptsmoke",
            dependencies: ["PTouchKit"]
        ),
        .executableTarget(
            name: "ptprint",
            dependencies: ["PTouchKit"]
        ),
        // Dev-only: rasterizes SVG icons → grayscale PNGs in PTouchKit/Resources/icons.
        // Not a product; run manually to (re)generate the bundled Bootstrap Icons.
        .executableTarget(
            name: "pticongen"
        ),
        // Dev-only: mints complimentary "redeem-by" unlock keys.
        .executableTarget(
            name: "btkeygen",
            dependencies: ["PTouchKit"]
        ),
        .testTarget(
            name: "PTouchKitTests",
            dependencies: ["PTouchKit"]
        ),
    ]
)
