// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CaylexChat",
    platforms: [.iOS("16.4")],
    products: [
        .library(name: "CaylexChat", targets: ["CaylexChat"])
    ],
    targets: [
        .target(
            name: "CaylexChat",
            resources: [.process("Resources")]
        ),
        .testTarget(name: "CaylexChatTests", dependencies: ["CaylexChat"])
    ]
)
