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
        .library(name: "ClickwillShared", targets: ["ClickwillShared"]),
        .library(name: "ClickwillDevice", targets: ["ClickwillDevice"]),
        .library(name: "ClickwillSongs", targets: ["ClickwillSongs"]),
        .library(name: "ClickwillArtists", targets: ["ClickwillArtists"]),
        .library(name: "ClickwillCD", targets: ["ClickwillCD"]),
        .executable(name: "ipodctl", targets: ["ipodctl"]),
    ],
    targets: [
        .target(name: "ITDBKit"),
        // The app's model layer: the library state, the change queue, the artwork cache.
        // No AppKit, so it can be tested with `swift test`.
        .target(name: "ClickwillModel", dependencies: ["ITDBKit"]),
        // What every screen module of the app shares: the theme, the error sentences, the
        // common views. A module takes shared things from here, never from another module or the app.
        .target(name: "ClickwillShared", dependencies: ["ITDBKit", "ClickwillModel"], path: "Sources/Shared"),
        // Screen modules. The app shows them through one file, App/Clickwill/Shell/Modules.swift,
        // so removing a module touches only its target here, App/project.yml and that file.
        .target(name: "ClickwillDevice", dependencies: ["ITDBKit", "ClickwillModel", "ClickwillShared"],
                path: "Sources/Device"),
        .target(name: "ClickwillSongs", dependencies: ["ITDBKit", "ClickwillModel", "ClickwillShared"],
                path: "Sources/Songs"),
        .target(name: "ClickwillArtists", dependencies: ["ITDBKit", "ClickwillModel", "ClickwillShared"],
                path: "Sources/Artists"),
        .target(name: "ClickwillCD", dependencies: ["ITDBKit", "ClickwillModel", "ClickwillShared"],
                path: "Sources/CD"),
        .executableTarget(name: "ipodctl", dependencies: ["ITDBKit", "ClickwillModel"]),
        .testTarget(name: "ITDBKitTests", dependencies: ["ITDBKit"]),
        // The `ipodctl` command tests use the fake iPod from the write tests.
        .testTarget(name: "ClickwillModelTests", dependencies: ["ClickwillModel", "ITDBKit", "ipodctl"]),
        .testTarget(name: "ClickwillSharedTests", dependencies: ["ClickwillShared"]),
        .testTarget(name: "ClickwillDeviceTests", dependencies: ["ClickwillDevice", "ITDBKit"]),
        .testTarget(name: "ClickwillSongsTests", dependencies: ["ClickwillSongs"]),
        .testTarget(name: "ClickwillArtistsTests", dependencies: ["ClickwillArtists"]),
        .testTarget(name: "ClickwillCDTests", dependencies: ["ClickwillCD"]),
    ]
)
