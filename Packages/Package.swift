// swift-tools-version: 6.0

import PackageDescription

let moduleReadmeExclude = ["README.md"]

let package = Package(
    name: "MacCleanupKit",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "Filesystem", targets: ["Filesystem"]),
        .library(name: "Index", targets: ["Index"]),
        .library(name: "Classification", targets: ["Classification"]),
        .library(name: "Identity", targets: ["Identity"]),
        .library(name: "Actions", targets: ["Actions"]),
        .library(name: "Analysis", targets: ["Analysis"]),
        .library(name: "Hints", targets: ["Hints"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "Filesystem",
            exclude: moduleReadmeExclude
        ),
        .target(
            name: "Index",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                "Identity",
            ],
            exclude: moduleReadmeExclude
        ),
        .target(
            name: "Classification",
            exclude: moduleReadmeExclude
        ),
        .target(
            name: "Identity",
            exclude: moduleReadmeExclude
        ),
        .target(
            name: "Actions",
            dependencies: ["Classification"],
            exclude: moduleReadmeExclude
        ),
        .target(
            name: "Hints",
            exclude: moduleReadmeExclude
        ),
        .target(
            name: "Analysis",
            dependencies: [
                "Filesystem",
                "Index",
                "Classification",
                "Identity",
                "Actions",
                "Hints",
            ],
            exclude: moduleReadmeExclude
        ),
        .testTarget(name: "FilesystemTests", dependencies: ["Filesystem"]),
        .testTarget(
            name: "IndexTests",
            dependencies: [
                "Index",
                "Identity",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(name: "ClassificationTests", dependencies: ["Classification"]),
        .testTarget(name: "IdentityTests", dependencies: ["Identity"]),
        .testTarget(name: "ActionsTests", dependencies: ["Actions"]),
        .testTarget(name: "AnalysisTests", dependencies: ["Analysis", "Classification", "Identity", "Index"]),
        .testTarget(name: "HintsTests", dependencies: ["Hints"]),
    ],
    swiftLanguageModes: [.v6]
)
