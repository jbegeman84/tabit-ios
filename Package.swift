// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Tabit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "TabitFormat", targets: ["TabitFormat"]),
        .executable(name: "tbt-inspect", targets: ["TBTInspect"]),
    ],
    targets: [
        .target(
            name: "CTabitCompression",
            linkerSettings: [.linkedLibrary("z")]
        ),
        .target(
            name: "TabitFormat",
            dependencies: ["CTabitCompression"]
        ),
        .executableTarget(
            name: "TBTInspect",
            dependencies: ["TabitFormat"]
        ),
        .testTarget(
            name: "TabitFormatTests",
            dependencies: ["TabitFormat"]
        ),
    ]
)
