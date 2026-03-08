// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "skrivned",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "skrivned",
            path: "Sources/Skrivned",
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AppKit"),
            ]
        ),
    ]
)
