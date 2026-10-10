import AppKit
import SoundcoreBarUI
import SwiftUI

@main
struct SoundcoreBarApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @AppStorage(MenuBarIcon.storageKey) private var iconRawValue = MenuBarIcon.default.rawValue

    var body: some Scene {
        MenuBarExtra {
            Panel(model: appDelegate.model)
        } label: {
            MenuBarIcon(rawValue: iconRawValue).label
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = HeadphonesModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
    }
}

private struct Panel: View {
    @ObservedObject var model: HeadphonesModel

    var body: some View {
        PanelView(
            items: model.items,
            bluetoothDenied: model.bluetoothDenied,
            onSelect: { id, mode in model.select(mode, for: id) },
            onOpenBluetoothSettings: {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") {
                    NSWorkspace.shared.open(url)
                }
            },
            onQuit: { NSApp.terminate(nil) }
        )
    }
}
