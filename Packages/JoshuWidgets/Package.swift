// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "JoshuWidgets",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "JoshuWidgets", targets: ["JoshuWidgets"])
    ],
    dependencies: [
        .package(path: "../JoshuKit")
    ],
    targets: [
        .target(name: "JoshuWidgets", dependencies: ["JoshuKit"]),
        .testTarget(name: "JoshuWidgetsTests", dependencies: ["JoshuWidgets"]),
    ]
)
