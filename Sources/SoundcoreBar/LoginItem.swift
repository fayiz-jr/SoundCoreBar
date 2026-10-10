// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 fayiz-jr

import Combine
import OSLog
import ServiceManagement

/// "Open at Login". macOS keeps this setting (System Settings › General › Login Items), where the
/// user can also change it, so it is read back from there each time the panel opens.
final class LoginItem: ObservableObject {
    @Published private(set) var isEnabled = false
    /// Registered, but switched off in System Settings; only the user can switch it back on there.
    @Published private(set) var needsApproval = false

    private let log = Logger(subsystem: "com.fayizjr.SoundcoreBar", category: "app")

    init() {
        refresh()
    }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        needsApproval = status == .requiresApproval
    }

    func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log.error("Couldn’t \(enabled ? "add" : "remove", privacy: .public) the login item: \(error.localizedDescription, privacy: .public)")
        }
        refresh()
        if enabled, needsApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}
