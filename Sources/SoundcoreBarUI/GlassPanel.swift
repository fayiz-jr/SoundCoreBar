// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 fayiz-jr

import AppKit
import SwiftUI

/// A borderless Liquid Glass panel that hangs under a menu bar item. It is as tall as its content,
/// scrolls when that would not fit on screen, and closes on a click elsewhere or Escape.
public final class GlassPanel: NSObject {
    private static var cornerRadius: CGFloat {
        if #available(macOS 26, *) { return 28 }
        return 18
    }
    private static let gapBelowMenuBar: CGFloat = 6
    private static let screenMargin: CGFloat = 8

    private let panel: AnchoredPanel
    private let glass: NSView
    private let width: CGFloat
    private let hosting: NSHostingView<MeasuredScrollView>
    private var contentHeight: CGFloat = 0
    private var anchor: NSRect?
    private var outsideClickMonitor: Any?
    private var defaultsObserver: NSObjectProtocol?
    /// When the panel last closed, so the click that closed it cannot also reopen it.
    public private(set) var lastClosed = Date.distantPast
    public var onClose: (() -> Void)?
    /// Called after every resize with the glass's frame on screen and the content's natural height.
    public var onLayout: ((NSRect, CGFloat) -> Void)?

    public var isOpen: Bool { panel.isVisible }
    public var window: NSWindow { panel }
    /// The visible glass on screen.
    public var glassFrame: NSRect { panel.frame }

    public init(width: CGFloat, content: AnyView) {
        self.width = width
        panel = AnchoredPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        glass = Self.makeGlassView()
        var report: (CGFloat) -> Void = { _ in }
        hosting = NSHostingView(rootView: MeasuredScrollView(content: content) { report($0) })
        super.init()
        report = { [weak self] height in self?.contentHeightChanged(height) }

        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The window server draws the shadow, around the window's visible pixels, as it does for
        // menus. The glass is clipped to its rounded shape (below), so that is all it traces; the
        // glass's own shadow, which filled the window's square corners, is clipped away with it.
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.onCancel = { [weak self] in self?.close() }

        // The panel sets its own size from the content height; the host must not push its SwiftUI
        // sizes onto the window as constraints.
        hosting.sizingOptions = []
        if #available(macOS 26, *), let glass = glass as? NSGlassEffectView {
            glass.contentView = hosting
        } else {
            hosting.frame = glass.bounds
            hosting.autoresizingMask = [.width, .height]
            glass.addSubview(hosting)
        }
        let clip = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 200))
        clip.wantsLayer = true
        clip.layer?.cornerRadius = Self.cornerRadius
        clip.layer?.cornerCurve = .continuous
        clip.layer?.masksToBounds = true
        glass.frame = clip.bounds
        glass.autoresizingMask = [.width, .height]
        clip.addSubview(glass)
        panel.contentView = clip
        applyGlassStyle()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyGlassStyle() }
        }
    }

    /// Opens the panel under `anchor`, a menu bar item's frame in screen coordinates.
    public func open(below anchor: NSRect) {
        self.anchor = anchor
        // Lay the content out first so its height is known before the panel appears.
        hosting.layoutSubtreeIfNeeded()
        updateFrame()
        panel.makeKeyAndOrderFront(nil)
        refreshShadow()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // A click on the menu bar item can arrive here too; the item toggles the panel itself.
                guard let self, !self.isOnAnchor(NSEvent.mouseLocation) else { return }
                self.close()
            }
        }
    }

    public func close() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        lastClosed = Date()
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        onClose?()
    }

    private func isOnAnchor(_ point: NSPoint) -> Bool {
        anchor?.insetBy(dx: -2, dy: -2).contains(point) ?? false
    }

    // MARK: Layout

    private func contentHeightChanged(_ height: CGFloat) {
        guard abs(height - contentHeight) > 0.5 else { return }
        contentHeight = height
        // This arrives in the middle of a SwiftUI update. Resizing the window right here left the
        // scroll view laid out for the old size (content pushed off the top, a blank strip below),
        // so the resize waits for the update to finish.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isVisible else { return }
            self.updateFrame()
        }
    }

    /// Keeps the top edge just under the menu bar, centred on the item but on screen, and the
    /// height that of the content, up to the bottom of the screen.
    private func updateFrame() {
        guard let anchor else { return }
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let top = min(anchor.minY, visible.maxY) - Self.gapBelowMenuBar
        let maxHeight = top - visible.minY - Self.screenMargin
        let height = min(max(contentHeight, 1), maxHeight).rounded(.up)
        let x = min(max(anchor.midX - width / 2, visible.minX + Self.screenMargin),
                    visible.maxX - width - Self.screenMargin)
        panel.anchoredTop = top
        panel.setFrame(NSRect(x: x, y: top - height, width: width, height: height), display: true)
        hosting.layoutSubtreeIfNeeded()
        refreshShadow()
        onLayout?(glassFrame, contentHeight)
    }

    /// The shadow is traced from what the window shows, so it is traced again once the new size
    /// has been drawn.
    private func refreshShadow() {
        panel.invalidateShadow()
        DispatchQueue.main.async { [weak self] in self?.panel.invalidateShadow() }
    }

    // MARK: Glass

    private static func makeGlassView() -> NSView {
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            return glass
        }
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        return effect
    }

    /// Regular glass by default, like the system's menus and Control Center. Clear glass shows
    /// much more of what is behind it, so it gets a light tint to keep the text readable.
    private func applyGlassStyle() {
        guard #available(macOS 26, *), let glass = glass as? NSGlassEffectView else { return }
        let clear = UserDefaults.standard.bool(forKey: PanelPreferences.clearGlassKey)
        glass.style = clear ? .clear : .regular
        glass.tintColor = clear ? NSColor.windowBackgroundColor.withAlphaComponent(0.45) : nil
    }
}

/// A borderless panel that can take the keyboard (for the custom icon field and Escape) without
/// activating the app, and whose top edge stays where it was put whatever resizes it.
private final class AnchoredPanel: NSPanel {
    var onCancel: (() -> Void)?
    var anchoredTop: CGFloat?

    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var frame = frameRect
        if let anchoredTop { frame.origin.y = anchoredTop - frame.height }
        super.setFrame(frame, display: flag)
    }
}

/// The content in a vertical scroll view, reporting the content's natural height.
struct MeasuredScrollView: View {
    let content: AnyView
    let onHeight: (CGFloat) -> Void

    var body: some View {
        ScrollView(.vertical) {
            content.background {
                GeometryReader { proxy in
                    Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                }
            }
        }
        .scrollIndicators(.automatic)
        .onPreferenceChange(ContentHeightKey.self) { height in
            MainActor.assumeIsolated { onHeight(height) }
        }
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
