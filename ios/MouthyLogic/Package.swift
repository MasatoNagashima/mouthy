// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MouthyLogic",
    products: [
        .library(name: "MouthyLogic", targets: ["MouthyLogic"]),
    ],
    targets: [
        .target(name: "MouthyLogic"),
        .testTarget(name: "MouthyLogicTests", dependencies: ["MouthyLogic"]),
    ]
)
