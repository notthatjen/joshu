// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "JoshuWidgets",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "JoshuWidgets", targets: ["JoshuWidgets"])
    ],
    dependencies: [
        .package(path: "../JoshuKit"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "JoshuWidgets",
            dependencies: [
                "JoshuKit",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]),
        .testTarget(name: "JoshuWidgetsTests", dependencies: ["JoshuWidgets"]),
    ]
)
