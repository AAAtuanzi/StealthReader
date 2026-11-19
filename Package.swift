// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StealthReader",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "StealthReader", targets: ["StealthReader"])
    ],
    targets: [
        .executableTarget(name: "StealthReader")
    ]
)
