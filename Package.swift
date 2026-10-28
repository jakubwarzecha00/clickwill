// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ITDBKit",
    platforms: [
        // The core and the model from macOS 14 - what the app supports since 0.3.0;
        // the app itself has its own target in App/project.yml.
        .macOS(.v14)
    ],
    products: [
        .library(name: "ITDBKit", targets: ["ITDBKit"]),
        .library(name: "ClickwillModel", targets: ["ClickwillModel"]),
        .executable(name: "ipodctl", targets: ["ipodctl"]),
    ],
    targets: [
        .target(name: "ITDBKit"),
        // The app's model layer: the library state, the change queue, the artwork cache.
        // No AppKit, so it can be tested with `swift test`.
        .target(name: "ClickwillModel", dependencies: ["ITDBKit"]),
        .executableTarget(name: "ipodctl", dependencies: ["ITDBKit", "ClickwillModel"]),
        .testTarget(name: "ITDBKitTests", dependencies: ["ITDBKit"]),
        // The `ipodctl` command tests use the fake iPod from the write tests.
        .testTarget(name: "ClickwillModelTests", dependencies: ["ClickwillModel", "ITDBKit", "ipodctl"]),
    ]
)
