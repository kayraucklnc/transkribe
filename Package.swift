// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Transkribe",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Transkribe", targets: ["Transkribe"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "1.1.0")
    ],
    targets: [
        .target(
            name: "TranskribeCore",
            dependencies: [.product(name: "WhisperKit", package: "WhisperKit")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Transkribe",
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
