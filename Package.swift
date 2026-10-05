// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Transkribe",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Transkribe", targets: ["Transkribe"]),
        .executable(name: "transkribe-mcp", targets: ["TranskribeMCP"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "1.1.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.17.5"),
    ],
    targets: [
        .target(
            name: "TranskribeCore",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Transkribe",
            dependencies: ["TranskribeCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "TranskribeMCP",
            dependencies: ["TranskribeCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "TranskribeCoreTests",
            dependencies: ["TranskribeCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
