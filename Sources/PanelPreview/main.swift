import AppKit
import SoundcoreBarUI
import SoundcoreKit
import SwiftUI

// Renders the menu bar panel with sample data to PNG files, in light and dark, since SwiftUI
// previews need Xcode. Usage: swift run PanelPreview [output directory]

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/preview")
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let earbuds = HeadphonesItem(id: "earbuds", name: "🐰soundcore R50i🦋", formFactor: .earbuds, state: .ready(.transparency))
let overEar = HeadphonesItem(id: "over-ear", name: "soundcore Q20i", formFactor: .overEar, state: .ready(.noiseCanceling))

func panel(_ items: [HeadphonesItem], denied: Bool = false, iconPicker: Bool = false) -> PanelView {
    PanelView(
        items: items, bluetoothDenied: denied, showsIconPicker: iconPicker,
        onSelect: { _, _ in }, onOpenBluetoothSettings: {}, onQuit: {}
    )
}

let scenarios: [(name: String, view: PanelView)] = [
    ("both-pairs", panel([earbuds, overEar])),
    ("icon-picker", panel([overEar], iconPicker: true)),
    ("connecting", panel([HeadphonesItem(id: "x", name: "soundcore Q20i", formFactor: .overEar, state: .connecting)])),
    ("none", panel([])),
    ("denied", panel([], denied: true)),
]

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

for (appearanceName, suffix) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
    for scenario in scenarios {
        let hosting = NSHostingView(rootView: scenario.view.background(.background))
        hosting.appearance = NSAppearance(named: appearanceName)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        // Glass and other layer effects only draw in a window that is on screen, so park one far
        // off to the side for a moment.
        let window = NSWindow(contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = hosting.appearance
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))

        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { continue }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let url = outputDirectory.appendingPathComponent("\(scenario.name)-\(suffix).png")
        try bitmap.representation(using: .png, properties: [:])?.write(to: url)
        print(url.path)
        window.orderOut(nil)
    }
}
