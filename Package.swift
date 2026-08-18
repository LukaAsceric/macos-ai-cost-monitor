// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacOSAICostMonitor",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MacOSAICostMonitor", targets: ["MacOSAICostMonitor"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6")
    ],
    targets: [
        .executableTarget(
            name: "MacOSAICostMonitor",
            dependencies: [
                .product(name: "Sparkle", package: "sparkle")
            ],
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
