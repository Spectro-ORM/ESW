// swift-tools-version: 6.3
import PackageDescription

// Development integration against peer checkouts; core ESW has no server deps.
let package = Package(
    name: "ESWLivePeregrine",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ESWLivePeregrine", targets: ["ESWLivePeregrine"]),
        .executable(name: "LiveDemo", targets: ["LiveDemo"]),
    ],
    dependencies: [
        .package(path: "../.."),
        .package(path: "../../../Peregrine"),
        .package(path: "../../../Nexus"),
    ],
    targets: [
        .target(name: "ESWLivePeregrine", dependencies: [
            .product(name: "ESWLive", package: "esw"),
            .product(name: "Peregrine", package: "peregrine"),
            .product(name: "Nexus", package: "nexus"),
        ]),
        .executableTarget(name: "LiveDemo", dependencies: ["ESWLivePeregrine"], path: "Examples/LiveDemo"),
        .testTarget(name: "ESWLivePeregrineTests", dependencies: [
            "ESWLivePeregrine", .product(name: "PeregrineTest", package: "peregrine"),
        ]),
    ],
    swiftLanguageModes: [.v6]
)
