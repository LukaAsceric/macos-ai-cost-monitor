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
                .linkedFramework("LocalAuthentication"),
                .linkedFramework("Security"),
                .linkedFramework("UserNotifications")
            ]
        ),
        .testTarget(
            name: "MacOSAICostMonitorTests",
            dependencies: ["MacOSAICostMonitor"],
            path: "Tests/MacOSAICostMonitorTests",
            resources: [.process("Fixtures")],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ],
            linkerSettings: [
                .linkedFramework("LocalAuthentication"),
                .linkedFramework("Security")
            ]
        )
    ]
)
