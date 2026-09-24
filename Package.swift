// swift-tools-version: 5.9
import PackageDescription

/// Oldest supported macOS. `create-app.sh` reads this line for the bundle's
/// `LSMinimumSystemVersion`.
let deploymentTarget = "14.0"

let package = Package(
    name: "WatchMeSleep",
    platforms: [
        .macOS(deploymentTarget)
    ],
    products: [
        .executable(
            name: "WatchMeSleep",
            targets: ["WatchMeSleep"]
        )
    ],
    dependencies: [
        // In-place updates from the appcast published with each release;
        // create-app.sh embeds and signs the framework.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(
            name: "WatchMeSleepCore",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/WatchMeSleepCore"
        ),
        .executableTarget(
            name: "WatchMeSleep",
            dependencies: ["WatchMeSleepCore"],
            path: "Sources/WatchMeSleep",
            // Swift Build, SwiftPM's default build system since Xcode 27, records
            // the deployment target as the SDK version in LC_BUILD_VERSION, and
            // macOS then runs the app in its pre-Tahoe compatibility look (no
            // Liquid Glass controls, untinted buttons, an empty Settings window at
            // launch). Stamp an SDK version instead: the manifest cannot ask
            // `xcrun`, so this is the floor that turns the Tahoe look on.
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-platform_version", "-Xlinker", "macos",
                              "-Xlinker", deploymentTarget, "-Xlinker", "26.0"])
            ]
        ),
        .testTarget(
            name: "WatchMeSleepTests",
            dependencies: ["WatchMeSleepCore"],
            path: "Tests"
        )
    ]
)
