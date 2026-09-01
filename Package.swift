// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TelePrompter",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TelePrompter", targets: ["TelePrompter"]),
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "TelePrompter",
            dependencies: [],
            path: "Sources/TelePrompter",
            exclude: ["Resources/Info.plist"],
            swiftSettings: [
                .unsafeFlags(["-framework", "AppKit",
                              "-framework", "AVFoundation",
                              "-framework", "Speech",
                              "-framework", "SwiftUI"])
            ]
        ),
    ]
)
