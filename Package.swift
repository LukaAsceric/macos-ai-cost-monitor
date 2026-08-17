// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacOSAICostMonitor",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MacOSAICostMonitor", targets: ["MacOSAICostMonitor"])
    ],
    targets: [
        .executableTarget(
            name: "MacOSAICostMonitor",
            path: "Sources/MacOSAICostMonitor",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Security")
            ]
        ),
        .testTarget(
            name: "MacOSAICostMonitorTests",
            dependencies: ["MacOSAICostMonitor"],
            path: "Tests/MacOSAICostMonitorTests",
            resources: [.process("Fixtures")],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
