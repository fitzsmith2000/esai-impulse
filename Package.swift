// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ESAIImpulse",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ESAIImpulse",
            path: "Sources/ESAIImpulse",
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("SwiftUI"),
                             .linkedFramework("ServiceManagement"), .linkedFramework("UserNotifications"),
                             .linkedFramework("Security")]
        )
    ]
)
