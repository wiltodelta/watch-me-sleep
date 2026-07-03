// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WatchMeSleep",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "WatchMeSleep",
            targets: ["WatchMeSleep"]
        )
    ],
    targets: [
        .target(
            name: "WatchMeSleepCore",
            path: "Sources/WatchMeSleepCore"
        ),
        .executableTarget(
            name: "WatchMeSleep",
            dependencies: ["WatchMeSleepCore"],
            path: "Sources/WatchMeSleep"
        ),
        .testTarget(
            name: "WatchMeSleepTests",
            dependencies: ["WatchMeSleepCore"],
            path: "Tests"
        )
    ]
)
