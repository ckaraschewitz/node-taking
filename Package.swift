// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "NodeTaking",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "NodeTaking",
            targets: ["NodeTaking"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "NodeTaking",
            path: "Sources/MinimalMarkdownNotes"
        ),
    ]
)
