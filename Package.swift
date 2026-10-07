// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CaylexChat",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "CaylexChat", targets: ["CaylexChat"])
    ],
    targets: [
        .target(
            name: "CaylexChat",
            resources: [.copy("Resources")]
        )
    ]
)
