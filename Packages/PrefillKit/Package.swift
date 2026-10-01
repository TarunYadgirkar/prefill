// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PrefillKit",
    platforms: [.iOS("27.0"), .macOS("26.0")],
    products: [
        .library(name: "PrefillKit", targets: ["PrefillKit"])
    ],
    targets: [
        .target(name: "PrefillKit"),
        .testTarget(name: "PrefillKitTests", dependencies: ["PrefillKit"])
    ]
)
