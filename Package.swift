// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-mtl",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "MTL",
            targets: ["MTL"]
        ),
        .executable(
            name: "swift-mtl",
            targets: ["swift-mtl"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.6.2"),
        .package(url: "https://github.com/mipalgu/swift-ecore", branch: "main"),
        .package(path: "../swift-aql"),
    ],
    targets: [
        .target(
            name: "MTL",
            dependencies: [
                .product(name: "ECore", package: "swift-ecore"),
                .product(name: "EMFBase", package: "swift-ecore"),
                .product(name: "OCL", package: "swift-ecore"),
                .product(name: "OrderedCollections", package: "swift-collections"),
                .product(name: "AQL", package: "swift-aql"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "swift-mtl",
            dependencies: [
                "MTL",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "ECore", package: "swift-ecore"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "MTLTests",
            dependencies: [
                "MTL",
                .product(name: "ECore", package: "swift-ecore"),
            ],
            resources: [
                .copy("Resources")
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
    ]
)
