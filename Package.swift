// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ClipShelf",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ClipShelf", targets: ["ClipShelf"])
    ],
    targets: [
        .target(
            name: "ClipShelfCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CryptoKit")
            ]
        ),
        .executableTarget(
            name: "ClipShelf",
            dependencies: ["ClipShelfCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        ),
        .testTarget(
            name: "ClipShelfCoreTests",
            dependencies: ["ClipShelfCore"]
        )
    ],
    swiftLanguageModes: [.v5]
)
