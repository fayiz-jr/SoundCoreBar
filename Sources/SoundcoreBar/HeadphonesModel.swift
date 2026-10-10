// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 fayiz-jr

import Combine
import SoundcoreBarUI
import SoundcoreBluetooth
import SoundcoreKit

/// Feeds the panel: turns the monitor's connections into `HeadphonesItem`s and routes clicks back.
final class HeadphonesModel: ObservableObject {
    @Published private(set) var items: [HeadphonesItem] = []
    @Published private(set) var bluetoothDenied = false

    private let monitor = HeadphonesMonitor()
    private let permission = BluetoothPermission()

    func start() {
        monitor.onChange = { [weak self] in self?.refresh() }
        // IOBluetooth must not be touched before Bluetooth access is granted.
        permission.request { [weak self] granted in
            if granted {
                self?.monitor.start()
            } else {
                self?.bluetoothDenied = true
            }
        }
    }

    func select(_ mode: AmbientSoundMode, for id: HeadphonesItem.ID) {
        monitor.connections.first { $0.address == id }?.setMode(mode)
    }

    func retry(_ id: HeadphonesItem.ID) {
        monitor.connections.first { $0.address == id }?.retryNow()
    }

    private func refresh() {
        items = monitor.connections.map { connection in
            HeadphonesItem(
                id: connection.address,
                name: connection.name,
                formFactor: connection.model?.formFactor,
                isBeta: connection.model.map { !$0.verified } ?? false,
                state: HeadphonesItem.State(connection.status)
            )
        }
    }
}

private extension HeadphonesItem.State {
    init(_ status: SoundcoreConnection.Status) {
        switch status {
        case .connecting: self = .connecting
        case .ready(let mode): self = .ready(mode)
        case .unsupported(let message): self = .unsupported(message)
        case .failed(let message): self = .problem(message)
        }
    }
}
