// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FTPServerKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
    ],
    products: [
        .library(name: "FTPServerKit", targets: ["FTPServerKit"]),
    ],
    targets: [
        .target(name: "FTPServerKit"),
        .testTarget(name: "FTPServerKitTests", dependencies: ["FTPServerKit"]),
    ]
)
