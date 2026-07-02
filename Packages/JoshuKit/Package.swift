// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "JoshuKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "JoshuKit", targets: ["JoshuKit"])
    ],
    targets: [
        .target(name: "JoshuKit"),
        .testTarget(name: "JoshuKitTests", dependencies: ["JoshuKit"]),
    ]
)
