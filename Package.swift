// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Wayline",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "WaylineCore", path: "Sources/WaylineCore"),
        .executableTarget(name: "Wayline", dependencies: ["WaylineCore"], path: "Sources/Wayline"),
        .executableTarget(name: "wayline-daemon", dependencies: ["WaylineCore"], path: "Sources/WaylineDaemon"),
    ]
)
