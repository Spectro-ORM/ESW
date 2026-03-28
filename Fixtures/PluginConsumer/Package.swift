// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "PluginConsumer",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(path: "../../"),
    ],
    targets: [
        .target(name: "Nexus"),
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "ESW", package: "esw"),
                "Nexus",
            ],
            plugins: [
                .plugin(name: "ESWBuildPlugin", package: "esw"),
            ]
        ),
    ]
)
