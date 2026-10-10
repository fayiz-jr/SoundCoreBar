// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 fayiz-jr

import AppKit
import SoundcoreBarUI
import SwiftUI

/// The menu bar icon. Clicking it opens or closes the glass panel; the icon follows the choice
/// made in the panel's icon picker.
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel: GlassPanel
    private var defaultsObserver: NSObjectProtocol?
    private var shownIcon: MenuBarIcon?
    private let loginItem = LoginItem()

    init(model: HeadphonesModel) {
        var closePanel: () -> Void = {}
        panel = GlassPanel(width: PanelView.width, content: AnyView(PanelContent(
            model: model, state: PanelState(), loginItem: loginItem, closePanel: { closePanel() }
        )))
        super.init()
        closePanel = { [weak self] in self?.panel.close() }
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePanel)
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }
        panel.onClose = { [weak self] in self?.statusItem.button?.highlight(false) }
        updateIcon()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateIcon() }
        }
    }

    @objc private func togglePanel() {
        if panel.isOpen {
            panel.close()
            return
        }
        // This click already closed the panel on its way here; it should not open it again.
        guard Date().timeIntervalSince(panel.lastClosed) > 0.3 else { return }
        guard let button = statusItem.button, let window = button.window else { return }
        // It may have been changed in System Settings since.
        loginItem.refresh()
        panel.open(below: window.convertToScreen(button.convert(button.bounds, to: nil)))
        button.highlight(true)
    }

    private func updateIcon() {
        let icon = MenuBarIcon(rawValue: UserDefaults.standard.string(forKey: MenuBarIcon.storageKey) ?? "")
        guard icon != shownIcon, let button = statusItem.button else { return }
        shownIcon = icon
        switch icon {
        case .symbol(let name):
            let image = NSImage(systemSymbolName: name, accessibilityDescription: "SoundcoreBar")
            image?.isTemplate = true
            button.image = image
            button.title = ""
        case .text(let text):
            button.image = nil
            button.title = text
        }
        button.setAccessibilityLabel("SoundcoreBar")
    }
}

/// Panel state that outlives the view, such as whether the icon picker is open.
final class PanelState: ObservableObject {
    @Published var showsIconPicker = false
}

private struct PanelContent: View {
    @ObservedObject var model: HeadphonesModel
    @ObservedObject var state: PanelState
    @ObservedObject var loginItem: LoginItem
    let closePanel: () -> Void

    var body: some View {
        PanelView(
            items: model.items,
            bluetoothDenied: model.bluetoothDenied,
            showsIconPicker: $state.showsIconPicker,
            onSelect: { id, mode in model.select(mode, for: id) },
            onRetry: { model.retry($0) },
            onSetUp: { id in
                closePanel()
                model.setUp(id)
            },
            onForget: { model.forget($0) },
            onOpenBluetoothSettings: {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") {
                    NSWorkspace.shared.open(url)
                }
            },
            onQuit: { NSApp.terminate(nil) },
            opensAtLogin: loginItem.isEnabled,
            loginItemNeedsApproval: loginItem.needsApproval,
            onSetOpenAtLogin: { loginItem.set($0) }
        )
    }
}
