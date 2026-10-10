// swift-tools-version: 6.2
import PackageDescription

let mainActorByDefault: [SwiftSetting] = [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "SoundcoreBar",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure protocol code (framing, models). No Bluetooth, so it is unit-testable.
        .target(name: "SoundcoreKit"),
        // IOBluetooth glue. Everything runs on the main thread, where IOBluetooth delivers callbacks.
        .target(
            name: "SoundcoreBluetooth",
            dependencies: ["SoundcoreKit"],
            swiftSettings: mainActorByDefault,
            linkerSettings: [.linkedFramework("IOBluetooth"), .linkedFramework("CoreBluetooth")]
        ),
        // The panel's SwiftUI views. They take plain data, so they can be previewed without Bluetooth.
        .target(
            name: "SoundcoreBarUI",
            dependencies: ["SoundcoreKit"],
            swiftSettings: mainActorByDefault
        ),
        // The menu bar app.
        .executableTarget(
            name: "SoundcoreBar",
            dependencies: ["SoundcoreKit", "SoundcoreBluetooth", "SoundcoreBarUI"],
            swiftSettings: mainActorByDefault
        ),
        // Renders the panel with sample data to PNGs (there are no SwiftUI previews without Xcode).
        .executableTarget(
            name: "PanelPreview",
            dependencies: ["SoundcoreKit", "SoundcoreBarUI"],
            swiftSettings: mainActorByDefault
        ),
        // Diagnostic tool: lists paired devices and RFCOMM services, dumps a state reply.
        .executableTarget(
            name: "SoundcoreProbe",
            dependencies: ["SoundcoreKit", "SoundcoreBluetooth"],
            swiftSettings: mainActorByDefault,
            linkerSettings: [.linkedFramework("IOBluetooth"), .linkedFramework("CoreBluetooth")]
        ),
        .testTarget(name: "SoundcoreKitTests", dependencies: ["SoundcoreKit"]),
    ]
)
