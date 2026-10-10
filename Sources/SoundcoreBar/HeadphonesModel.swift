// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 fayiz-jr

import Combine
import Foundation
import SoundcoreBarUI
import SoundcoreBluetooth
import SoundcoreKit

/// Feeds the panel: turns the monitor's connections into `HeadphonesItem`s and routes clicks back.
/// Also keeps the models learned with the setup assistant.
final class HeadphonesModel: ObservableObject {
    @Published private(set) var items: [HeadphonesItem] = []
    @Published private(set) var bluetoothDenied = false

    private let monitor = HeadphonesMonitor()
    private let permission = BluetoothPermission()
    private var learned = LearnedModels.load()
    private var setupWindow: SetupWindowController?

    func start() {
        monitor.models = knownModels
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

    /// The built-in models, then the learned ones. Started with `-SetUpKnownHeadphones YES`, only
    /// the learned ones, so the setup assistant can be tried on supported headphones.
    private var knownModels: [HeadphoneModel] {
        UserDefaults.standard.bool(forKey: "SetUpKnownHeadphones") ? learned : HeadphoneModels.builtIn + learned
    }

    func select(_ mode: AmbientSoundMode, for id: HeadphonesItem.ID) {
        connection(id)?.setMode(mode)
    }

    func retry(_ id: HeadphonesItem.ID) {
        connection(id)?.retryNow()
    }

    func setUp(_ id: HeadphonesItem.ID) {
        if let setupWindow {
            // One pair at a time.
            setupWindow.show()
            return
        }
        guard let connection = connection(id) else { return }
        let assistant = SetupAssistant(connection: connection) { [weak self] model in self?.learn(model) }
        let window = SetupWindowController(assistant: assistant, address: id)
        window.onClose = { [weak self] in self?.setupWindow = nil }
        setupWindow = window
        window.show()
    }

    func forget(_ id: HeadphonesItem.ID) {
        guard let model = connection(id)?.model else { return }
        learned.removeAll { $0 == model }
        LearnedModels.save(learned)
        monitor.models = knownModels
    }

    private func learn(_ model: HeadphoneModel) {
        learned.removeAll { $0.id == model.id }
        learned.append(model)
        LearnedModels.save(learned)
        monitor.models = knownModels
    }

    private func connection(_ id: HeadphonesItem.ID) -> SoundcoreConnection? {
        monitor.connections.first { $0.address == id }
    }

    private func refresh() {
        items = monitor.connections.map { connection in
            HeadphonesItem(
                id: connection.address,
                name: connection.name,
                formFactor: connection.model?.formFactor,
                badge: connection.model.flatMap { model in
                    learned.contains(model) ? .learned : (model.verified ? nil : .beta)
                },
                state: HeadphonesItem.State(connection.status)
            )
        }
        if let setupWindow {
            setupWindow.assistant.connectionChanged(isConnected: connection(setupWindow.address) != nil)
        }
    }
}

/// Models taught with the setup assistant, kept in the app's defaults.
enum LearnedModels {
    private static let key = "learnedModels"

    static func load() -> [HeadphoneModel] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([HeadphoneModel].self, from: data)) ?? []
    }

    static func save(_ models: [HeadphoneModel]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(models), forKey: key)
    }
}

private extension HeadphonesItem.State {
    init(_ status: SoundcoreConnection.Status) {
        switch status {
        case .connecting: self = .connecting
        case .ready(let mode): self = .ready(mode)
        case .unsupported(let message): self = .unsupported(message)
        case .failed(let message): self = .problem(message)
        case .settingUp: self = .settingUp
        }
    }
}
