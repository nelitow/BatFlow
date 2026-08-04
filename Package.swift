// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BatFlow",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "BatFlow",
            targets: ["BatFlow"]
        )
    ],
    targets: [
        .executableTarget(
            name: "BatFlow",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        )
    ]
)
