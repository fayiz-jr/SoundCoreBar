// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 fayiz-jr

import Foundation
@preconcurrency import IOBluetooth
import OSLog
import SoundcoreKit

/// Follows Bluetooth connections and keeps a `SoundcoreConnection` for every connected device that
/// may be Soundcore headphones, in the order they connected. Each connection works out the model
/// from the headphones' answer.
public final class HeadphonesMonitor: NSObject {
    public private(set) var connections: [SoundcoreConnection] = []
    /// Called whenever a pair connects or disconnects, or a connection's status changes.
    public var onChange: (() -> Void)?

    /// Headphones that just connected are still setting up their audio profiles; give them a moment
    /// before opening the control channel.
    private static let settleDelay: Duration = .seconds(1.5)

    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    private let log = Logger(subsystem: "com.fayizjr.SoundcoreBar", category: "monitor")

    /// The models connections may recognise.
    public var models: [HeadphoneModel] = HeadphoneModels.builtIn

    public override init() {}

    public func start() {
        guard connectNotification == nil else { return }
        // Attach what is already connected first: registering also reports those devices as
        // newly connected, which would delay them by the settle time.
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        for device in paired where device.isConnected() {
            attach(device, after: .zero)
        }
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self, selector: #selector(deviceConnected(_:device:))
        )
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        attach(device, after: Self.settleDelay)
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard let address = device.addressString else { return }
        disconnectNotifications.removeValue(forKey: address)?.unregister()
        guard let index = connections.firstIndex(where: { $0.address == address }) else { return }
        let connection = connections.remove(at: index)
        log.info("\(connection.name, privacy: .public) disconnected")
        connection.close()
        onChange?()
    }

    private func attach(_ device: IOBluetoothDevice, after delay: Duration) {
        guard let address = device.addressString,
              !connections.contains(where: { $0.address == address }),
              isCandidate(device)
        else { return }

        log.info("\(device.name ?? address, privacy: .public) connected")
        disconnectNotifications[address] = device.register(
            forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:))
        )
        let connection = SoundcoreConnection(device: device, models: models)
        connection.onChange = { [weak self] in self?.onChange?() }
        connections.append(connection)
        onChange?()

        Task { [weak connection] in
            try? await Task.sleep(for: delay)
            connection?.start()
        }
    }

    /// Soundcore by name, or renamed headphones that offer Soundcore's control service. Services
    /// are only known once macOS has looked them up, which it does when the device first pairs.
    private func isCandidate(_ device: IOBluetoothDevice) -> Bool {
        HeadphoneModels.isCandidate(deviceName: device.name ?? "", among: models)
            || device.rfcommServices.contains { $0.serviceClassUUIDs.contains(where: SoundcoreServiceUUID.isVendor) }
    }
}
