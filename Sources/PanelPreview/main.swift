// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 fayiz-jr

import AppKit
import SoundcoreBarUI
import SoundcoreKit
import SwiftUI

// Previews the menu bar panel with sample data, since SwiftUI previews need Xcode.
//
//   PanelPreview [output directory]   renders PNGs in light and dark (layout only: the capture
//                                     cannot draw Liquid Glass)
//   PanelPreview --live               opens the real glass panel under the top right corner of the
//                                     screen, opens and closes the icon picker, and prints the
//                                     window, content and scroll geometry after each step
//   PanelPreview --live --hold <s>    the same, then keeps the panel open for <s> seconds (for a
//                                     screenshot); --clear holds it with Clear Glass, --badges shows
//                                     Beta, Learned and unsupported headphones instead
//   PanelPreview --screenshot <file.png> [--dark]
//                                     the README picture: the real glass panel over a plain backdrop
//                                     drawn by this tool, so nothing else on screen shows through

let badgeSample = [
    HeadphonesItem(id: "learned", name: "soundcore Space Q46", formFactor: .overEar, badge: .learned, state: .ready(.normal)),
    HeadphonesItem(id: "beta", name: "soundcore Liberty 4 Pro", formFactor: .earbuds, badge: .beta, state: .ready(.transparency)),
    HeadphonesItem(id: "unknown", name: "soundcore Motion+", formFactor: nil, state: .unsupported("This model isn’t supported yet.")),
]
let earbuds = HeadphonesItem(id: "earbuds", name: "🐰soundcore R50i🦋", formFactor: .earbuds, state: .ready(.transparency))
let overEar = HeadphonesItem(id: "over-ear", name: "soundcore Q20i", formFactor: .overEar, state: .ready(.noiseCanceling))

func panel(_ items: [HeadphonesItem], denied: Bool = false, iconPicker: Binding<Bool> = .constant(false)) -> PanelView {
    PanelView(
        items: items, bluetoothDenied: denied, showsIconPicker: iconPicker,
        onSelect: { _, _ in }, onOpenBluetoothSettings: {}, onQuit: {}
    )
}

// MARK: Setup assistant

let noSetupActions = SetupActions(
    start: {}, setFormFactor: { _ in }, record: { _ in }, skip: { _ in }, test: {}, answer: { _ in },
    copyReport: {}, openIssues: {}, close: {}
)

let sampleReport = """
### Headphones set up in SoundcoreBar

- Bluetooth name: soundcore Space Q46
- SoundcoreBar 1.1
- Sound modes: byte 49, 6 bytes; change notices repeat the whole block
- Recognition: serial number at byte 7, starting 3046
- Test switch: worked
"""

let setupScenarios: [(name: String, state: SetupState)] = [
    ("setup-intro", SetupState(deviceName: "soundcore Space Q46", formFactor: .overEar)),
    ("setup-record", SetupState(deviceName: "soundcore Space Q46", formFactor: .overEar, step: .record(.transparency),
                                recorded: [.noiseCanceling], noticesSeen: 1)),
    ("setup-found", SetupState(deviceName: "soundcore Space Q46", formFactor: .overEar, step: .found(
        location: "It’s byte 49 of their settings, in a 6-byte block. They’ll be recognised by their serial number, even if renamed.",
        target: .transparency), recorded: [.noiseCanceling, .transparency, .normal], noticesSeen: 3)),
    ("setup-confirm", SetupState(deviceName: "soundcore Space Q46", formFactor: .overEar, step: .confirm(.transparency))),
    ("setup-done", SetupState(deviceName: "soundcore Space Q46", formFactor: .overEar, step: .done, report: sampleReport)),
    ("setup-failed", SetupState(deviceName: "soundcore Space Q46", formFactor: .overEar, step: .failed(
        "The headphones never announced a change. Switch them with their own button, not the Soundcore app, and try again."),
        report: sampleReport)),
]

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

if let index = CommandLine.arguments.firstIndex(of: "--screenshot"), CommandLine.arguments.indices.contains(index + 1) {
    runScreenshot(to: CommandLine.arguments[index + 1], dark: CommandLine.arguments.contains("--dark"))
} else if CommandLine.arguments.contains("--live") {
    runLive()
} else {
    try renderImages(to: URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/preview"))
}

func renderImages(to outputDirectory: URL) throws {
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    let scenarios: [(name: String, view: AnyView)] = [
        ("both-pairs", AnyView(panel([earbuds, overEar]))),
        ("icon-picker", AnyView(panel([overEar], iconPicker: .constant(true)))),
        ("connecting", AnyView(panel([HeadphonesItem(id: "x", name: "soundcore Q20i", formFactor: .overEar, state: .connecting)]))),
        ("beta-and-unsupported", AnyView(panel([
            HeadphonesItem(id: "beta", name: "soundcore Liberty 4 Pro", formFactor: .earbuds, badge: .beta, state: .ready(nil)),
            HeadphonesItem(id: "learned", name: "soundcore Space Q46", formFactor: .overEar, badge: .learned,
                           state: .connecting),
            HeadphonesItem(id: "setting-up", name: "soundcore Liberty 4", formFactor: nil, state: .settingUp),
            HeadphonesItem(id: "unknown", name: "soundcore Motion+", formFactor: nil,
                           state: .unsupported("This model isn’t supported yet.")),
        ]))),
        ("none", AnyView(panel([]))),
        ("denied", AnyView(panel([], denied: true))),
    ] + setupScenarios.map { ($0.name, AnyView(SetupView(state: $0.state, actions: noSetupActions))) }
    for (appearanceName, suffix) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
        for scenario in scenarios {
            let hosting = NSHostingView(rootView: scenario.view.background(.background))
            hosting.appearance = NSAppearance(named: appearanceName)
            hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
            // Layer effects only draw in a window that is on screen, so park one far off to the side.
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
}

final class LiveState: ObservableObject {
    @Published var showsIconPicker = false
}

struct LiveContent: View {
    @ObservedObject var state: LiveState
    var body: some View {
        panel(CommandLine.arguments.contains("--badges") ? badgeSample : [earbuds, overEar],
              iconPicker: $state.showsIconPicker)
    }
}

func runLive() {
    let state = LiveState()
    let glass = GlassPanel(width: PanelView.width, content: AnyView(LiveContent(state: state)))
    glass.onLayout = { frame, contentHeight in
        print("  layout: glass \(frame.integral) content height \(Int(contentHeight))")
    }
    let screen = NSScreen.main!.frame
    let anchor = NSRect(x: screen.maxX - 220, y: NSScreen.main!.visibleFrame.maxY, width: 24, height: 24)

    func report(_ step: String) {
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        let frame = glass.glassFrame
        let scroll = glass.window.contentView.flatMap(findScrollView)
        let offset = scroll.map { Int($0.contentView.bounds.origin.y) } ?? -1
        let document = scroll?.documentView.map { Int($0.frame.height) } ?? -1
        let viewport = scroll.map { Int($0.contentView.bounds.height) } ?? -1
        let underMenuBar = abs(frame.maxY - (anchor.minY - 6)) < 1
        print("\(step): glass height \(Int(frame.height)), top under menu bar \(underMenuBar), "
              + "viewport \(viewport), document \(document), scroll offset \(offset)")
    }

    glass.open(below: anchor)
    report("opened")
    state.showsIconPicker = true
    report("icon picker open")
    state.showsIconPicker = false
    report("icon picker closed")
    state.showsIconPicker = true
    report("icon picker open again")
    if let seconds = CommandLine.arguments.firstIndex(of: "--hold")
        .flatMap({ CommandLine.arguments.indices.contains($0 + 1) ? Double(CommandLine.arguments[$0 + 1]) : nil }) {
        state.showsIconPicker = false
        UserDefaults.standard.set(CommandLine.arguments.contains("--clear"), forKey: PanelPreferences.clearGlassKey)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        print("holding at glass \(glass.glassFrame.integral) for \(seconds) s")
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
    glass.close()
    exit(0)
}

func findScrollView(in view: NSView) -> NSScrollView? {
    if let scroll = view as? NSScrollView { return scroll }
    for subview in view.subviews {
        if let found = findScrollView(in: subview) { return found }
    }
    return nil
}

// MARK: README screenshot

func runScreenshot(to path: String, dark: Bool) {
    app.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    UserDefaults.standard.set(false, forKey: PanelPreferences.clearGlassKey)
    let items = [
        HeadphonesItem(id: "earbuds", name: "soundcore R50i NC", formFactor: .earbuds, state: .ready(.transparency)),
        HeadphonesItem(id: "over-ear", name: "soundcore Q20i", formFactor: .overEar, state: .ready(.noiseCanceling)),
    ]
    let glass = GlassPanel(width: PanelView.width, content: AnyView(panel(items)))
    // Away from the menu bar, so the picture holds only the panel and the backdrop.
    let screen = NSScreen.main!.frame
    glass.open(below: NSRect(x: screen.midX - 12, y: screen.midY + 260, width: 24, height: 24))
    RunLoop.main.run(until: Date().addingTimeInterval(0.8))

    let margin: CGFloat = 44
    let area = glass.glassFrame.insetBy(dx: -margin, dy: -margin).integral
    let backdrop = NSWindow(contentRect: area, styleMask: .borderless, backing: .buffered, defer: false)
    backdrop.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)
    backdrop.contentView = BackdropView(dark: dark)
    backdrop.orderFrontRegardless()
    RunLoop.main.run(until: Date().addingTimeInterval(1.2))

    // screencapture counts from the top left of the main display.
    let region = "\(Int(area.minX)),\(Int(screen.maxY - area.maxY)),\(Int(area.width)),\(Int(area.height))"
    let capture = Process()
    capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    capture.arguments = ["-x", "-R", region, path]
    try? capture.run()
    capture.waitUntilExit()
    print(capture.terminationStatus == 0 ? path : "screencapture failed (\(capture.terminationStatus))")
    glass.close()
    backdrop.orderOut(nil)
    exit(capture.terminationStatus)
}

/// A soft gradient for the glass to sit on, in the spirit of the macOS wallpapers.
final class BackdropView: NSView {
    init(dark: Bool) {
        super.init(frame: .zero)
        wantsLayer = true
        let gradient = CAGradientLayer()
        gradient.colors = (dark
            ? [NSColor(srgbRed: 0.10, green: 0.09, blue: 0.27, alpha: 1), NSColor(srgbRed: 0.33, green: 0.16, blue: 0.47, alpha: 1),
               NSColor(srgbRed: 0.05, green: 0.33, blue: 0.43, alpha: 1)]
            : [NSColor(srgbRed: 0.78, green: 0.80, blue: 1.00, alpha: 1), NSColor(srgbRed: 0.98, green: 0.80, blue: 0.86, alpha: 1),
               NSColor(srgbRed: 0.75, green: 0.93, blue: 0.96, alpha: 1)]).map(\.cgColor)
        gradient.startPoint = CGPoint(x: 0, y: 1)
        gradient.endPoint = CGPoint(x: 1, y: 0)
        layer = gradient
    }

    required init?(coder: NSCoder) { nil }
}
