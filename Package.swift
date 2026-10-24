// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PushbulletTray",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "PushbulletTray",
            swiftSettings: [.unsafeFlags(["-Osize"], .when(configuration: .release))]
        ),
        .testTarget(
            name: "PushbulletTrayTests",
            dependencies: ["PushbulletTray"]
        ),
    ]
)
