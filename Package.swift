// swift-tools-version: 6.3

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "swift-esw",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "ESW",
            targets: ["ESW"]
        ),
        .library(
            name: "ESWCompilerLib",
            targets: ["ESWCompilerLib"]
        ),
        .plugin(
            name: "ESWBuildPlugin",
            targets: ["ESWBuildPlugin"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
        .package(url: "https://github.com/apple/swift-algorithms.git", from: "1.2.1"),
    ],
    targets: [
        // Runtime library — ESWValue + escape() + macro declarations.
        .target(
            name: "ESW",
            dependencies: ["ESWMacros"]
        ),

        // Compile-time macro implementation — #render and #esw.
        .macro(
            name: "ESWMacros",
            dependencies: [
                .product(name: "Algorithms", package: "swift-algorithms"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                "ESWCompilerLib",
            ]
        ),

        // Tokenizer + code generator, testable library.
        .target(
            name: "ESWCompilerLib",
            dependencies: [
                .product(name: "Algorithms", package: "swift-algorithms")
            ]
        ),

        // Thin CLI wrapper around ESWCompilerLib.
        .executableTarget(
            name: "ESWCompilerCLI",
            dependencies: ["ESWCompilerLib"]
        ),

        // SPM Build Tool Plugin.
        .plugin(
            name: "ESWBuildPlugin",
            capability: .buildTool(),
            dependencies: ["ESWCompilerCLI"]
        ),

        // Tests
        .testTarget(
            name: "ESWTests",
            dependencies: ["ESW"]
        ),
        .testTarget(
            name: "ESWCompilerLibTests",
            dependencies: ["ESWCompilerLib"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
