// swift-tools-version:5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "bclm_loop",
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "0.1.0")
    ],
    targets: [
        .target(
            name: "bclm_loop",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]),
    ]
)
