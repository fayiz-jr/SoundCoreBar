// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 fayiz-jr

import AppKit
@preconcurrency import IOBluetooth
import SoundcoreBluetooth
import SoundcoreKit

// Diagnostic tool. Run it with scripts/probe.sh so it launches as its own app and gets its own
// Bluetooth permission.
//
// 1. Lists every paired device with its cached RFCOMM services.
// 2. For each connected Soundcore device: refreshes SDP, opens the preferred RFCOMM service,
//    sends Request State (resending like OpenSCQ30 if there is no reply) and prints every packet
//    received during the listen window. Press the mode button during that window to capture the
//    "sound modes changed" packet.
//
// Arguments:
//   --listen <seconds>   how long to keep each channel open (default 5)
//   --device <text>      only probe devices whose name contains <text>
//                        (default: names containing "soundcore", or devices with the vendor service)
//   --send <hex>         after the first state reply, send one outbound packet given as command
//                        and body (e.g. "06 81 00 ff ff 01"), then request the state again
//   --cycle <n>          after the first state reply, switch to the next mode n times, 2.5 s
//                        apart, re-reading the state 2 s after each switch, and count how many stuck
//   --state-after-ack    with --cycle: also request the state right after each acknowledgement
//   --set <modes>        instead of dumping, switch the first matching connected pair to
//                        nc | transparency | normal through the app's SoundcoreConnection, printing
//                        every packet, then report the mode the headphones confirm. Several modes
//                        separated by commas are clicked 0.3 s apart, like quick menu clicks.

setvbuf(stdout, nil, _IOLBF, 0)

final class Probe: NSObject {
    private let listenSeconds: Double
    private let deviceFilter: String?
    private let targetModes: [AmbientSoundMode]
    private let extraPacket: Packet?
    private let started = Date()
    private let permission = BluetoothPermission()
    private var connection: SoundcoreConnection?
    private var setRequested = false
    private var queue: [IOBluetoothDevice] = []
    private var device: IOBluetoothDevice?
    private var channel: IOBluetoothRFCOMMChannel?
    private var parser = PacketStreamParser()
    private var stateReceived = false
    private var channelReady = false
    private var sdpQueryTask: Task<Void, Never>?
    private var summary: [String] = []
    private let cycleCount: Int
    private let stateAfterAck: Bool
    private var model: (any HeadphoneModel)?
    private var lastModes: SoundModes?

    init(listenSeconds: Double, deviceFilter: String?, targetModes: [AmbientSoundMode], extraPacket: Packet?,
         cycleCount: Int, stateAfterAck: Bool) {
        self.cycleCount = cycleCount
        self.stateAfterAck = stateAfterAck
        self.listenSeconds = listenSeconds
        self.deviceFilter = deviceFilter
        self.targetModes = targetModes
        self.extraPacket = extraPacket
    }

    func start() {
        log("SoundcoreProbe on macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        Task {
            try? await Task.sleep(for: .seconds(180))
            self.finish(reason: "overall timeout reached")
        }
        permission.request { granted in
            guard granted else {
                self.finish(reason: "Bluetooth permission denied. Enable SoundcoreProbe in System Settings > "
                    + "Privacy & Security > Bluetooth, then run again.")
                return
            }
            if !self.targetModes.isEmpty {
                self.switchModes(self.targetModes)
            } else {
                self.listDevices()
            }
        }
    }

    // MARK: Switching through SoundcoreConnection

    private func switchModes(_ targets: [AmbientSoundMode]) {
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        guard let device = paired.first(where: { $0.isConnected() && isCandidate($0) }),
              let model = HeadphoneModels.model(forDeviceName: device.name ?? "")
        else {
            finish(reason: "No connected, supported headphones match.")
            return
        }
        log("Switching \"\(device.name ?? "?")\" (\(model.modelNumber)) to "
            + targets.map(\.title).joined(separator: " → "))
        let connection = SoundcoreConnection(device: device, model: model)
        self.connection = connection
        connection.trace = { [weak self] line in self?.log("   " + line) }
        connection.onChange = { [weak self] in self?.connectionChanged(targets: targets) }
        connection.start()
    }

    private func connectionChanged(targets: [AmbientSoundMode]) {
        guard let connection else { return }
        log("status: \(connection.status)")
        guard case .ready(let mode) = connection.status, !setRequested else { return }
        setRequested = true
        log("current mode: \(mode.title)")
        Task {
            for (index, target) in targets.enumerated() {
                if index > 0 { try? await Task.sleep(for: .milliseconds(300)) }
                self.log("click: \(target.title)")
                connection.setMode(target)
            }
            // Wait past every switch's settle time (and any confirming state read), then report.
            try? await Task.sleep(for: .seconds(3 + 1.5 * Double(targets.count)))
            self.finishSwitch(remark: "last click was \(targets.last!.title)")
        }
    }

    private func finishSwitch(remark: String?) {
        guard let connection else { return }
        if let remark { log(remark) }
        if case .ready(let mode) = connection.status {
            note("\(connection.name): headphones report \(mode.title)")
        } else {
            note("\(connection.name): status \(connection.status)")
        }
        connection.close()
        finish(reason: "done")
    }

    // MARK: Listing

    private func listDevices() {
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        log("")
        log("== Paired devices (\(paired.count)) ==")
        for device in paired {
            log("* \"\(device.name ?? "(no name)")\"  address=\(device.addressString ?? "?")  "
                + "connected=\(device.isConnected())  "
                + "class=0x\(String(device.classOfDevice, radix: 16))")
            printServices(device.rfcommServices, heading: "cached RFCOMM services")
        }
        queue = paired.filter { $0.isConnected() && isCandidate($0) }
        log("")
        if queue.isEmpty {
            finish(reason: "No connected Soundcore device found. Connect the headphones and run again.")
            return
        }
        log("Will probe: " + queue.map { "\"\($0.name ?? "?")\"" }.joined(separator: ", "))
        probeNext()
    }

    private func isCandidate(_ device: IOBluetoothDevice) -> Bool {
        let name = device.name ?? ""
        if let deviceFilter { return name.localizedCaseInsensitiveContains(deviceFilter) }
        return name.localizedCaseInsensitiveContains("soundcore")
            || device.rfcommServices.contains { $0.serviceClassUUIDs.contains(where: SoundcoreServiceUUID.isVendor) }
    }

    private func printServices(_ services: [RFCOMMService], heading: String) {
        if services.isEmpty {
            log("    (\(heading): none)")
            return
        }
        log("    \(heading):")
        for service in services {
            let uuids = service.serviceClassUUIDs.map { uuid in
                let text = uuid.uuidString.lowercased()
                return SoundcoreServiceUUID.isVendor(uuid) ? text + " [soundcore vendor]" : text
            }
            log("      - channel \(service.channelID)  name=\"\(service.name ?? "")\"  uuids=\(uuids)")
        }
    }

    // MARK: Probing one device

    private func probeNext() {
        guard !queue.isEmpty else {
            finish(reason: "done")
            return
        }
        let device = queue.removeFirst()
        self.device = device
        model = HeadphoneModels.model(forDeviceName: device.name ?? "")
        lastModes = nil
        stateReceived = false
        channelReady = false
        parser.reset()
        log("")
        log("== Probing \"\(device.name ?? "?")\" (\(device.addressString ?? "?")) ==")
        log("Refreshing SDP records…")
        let status = device.performSDPQuery(self)
        if status != kIOReturnSuccess {
            log("performSDPQuery failed (\(hex(status))); using cached records")
            openChannel(on: device)
            return
        }
        sdpQueryTask = Task {
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            self.log("SDP query timed out; using cached records")
            self.openChannel(on: device)
        }
    }

    @objc func sdpQueryComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        guard device == self.device, sdpQueryTask != nil else { return }
        sdpQueryTask?.cancel()
        sdpQueryTask = nil
        log("SDP query finished with status \(hex(status))")
        openChannel(on: device)
    }

    private func dumpSDPRecords(of device: IOBluetoothDevice) {
        let records = (device.services as? [IOBluetoothSDPServiceRecord]) ?? []
        log("    raw SDP records (\(records.count)):")
        for record in records {
            var channelID: BluetoothRFCOMMChannelID = 0
            let rfcomm = record.getRFCOMMChannelID(&channelID) == kIOReturnSuccess ? "rfcomm \(channelID)" : "no rfcomm"
            let attributes = (record.attributes as? [NSNumber: IOBluetoothSDPDataElement]) ?? [:]
            let ids = attributes.keys.map { String(format: "0x%04x", $0.intValue) }.sorted()
            log("      - \"\(record.getServiceName() ?? "")\" \(rfcomm) attributes=\(ids)")
            if let classList = attributes[NSNumber(value: 0x0001)] {
                log("        0x0001 type=\(classList.getTypeDescriptor()) size=\(classList.getSize()) value=\(classList)")
                for element in (classList.getArrayValue() as? [IOBluetoothSDPDataElement]) ?? [] {
                    let uuid = element.getUUIDValue()
                    let raw = uuid.map { [UInt8](Data(referencing: $0)).hexString } ?? "nil"
                    let full = uuid?.getWithLength(16).map { [UInt8](Data(referencing: $0)).hexString } ?? "nil"
                    log("          element type=\(element.getTypeDescriptor()) size=\(element.getSize()) uuid=\(raw) uuid128=\(full)")
                }
            }
        }
    }

    private func openChannel(on device: IOBluetoothDevice) {
        sdpQueryTask?.cancel()
        sdpQueryTask = nil
        dumpSDPRecords(of: device)
        let services = device.rfcommServices
        printServices(services, heading: "RFCOMM services")
        guard let service = SoundcoreServiceUUID.preferredService(in: services) else {
            note("\(device.name ?? "?"): no Soundcore vendor or Serial Port service found")
            probeNext()
            return
        }
        log("Opening RFCOMM channel \(service.channelID) (\(service.name ?? "unnamed"))…")
        summary.append("\(device.name ?? "?"): service \"\(service.name ?? "")\" channel \(service.channelID) "
            + "uuids \(service.serviceClassUUIDs.map { $0.uuidString.lowercased() })")
        var newChannel: IOBluetoothRFCOMMChannel?
        let status = device.openRFCOMMChannelAsync(&newChannel, withChannelID: service.channelID, delegate: self)
        guard status == kIOReturnSuccess else {
            note("\(device.name ?? "?"): openRFCOMMChannelAsync failed with \(hex(status))")
            probeNext()
            return
        }
        channel = newChannel
        Task {
            try? await Task.sleep(for: .seconds(10))
            guard !self.channelReady, self.channel == newChannel else { return }
            self.note("\(device.name ?? "?"): RFCOMM open timed out")
            self.closeChannel()
        }
    }

    private func channelOpened() {
        channelReady = true
        log("Channel open. Listening for \(listenSeconds)s.")
        Task {
            for (attempt, wait) in [0.5, 1.0, 1.5].enumerated() where !self.stateReceived {
                self.send(Packet.requestState, label: "Request State (attempt \(attempt + 1))")
                try? await Task.sleep(for: .seconds(wait))
            }
            if !self.stateReceived {
                self.note("\(self.device?.name ?? "?"): no 01 01 state reply after 3 attempts")
            }
        }
        guard cycleCount == 0 else { return }  // the cycle closes the channel itself
        Task {
            try? await Task.sleep(for: .seconds(self.listenSeconds))
            self.closeChannel()
        }
    }

    private func runCycle() {
        Task {
            var stuck = 0
            for round in 1...self.cycleCount {
                guard let model = self.model, let current = self.lastModes else { break }
                let target = AmbientSoundMode(rawValue: (current.ambient.rawValue + 1) % 3)!
                self.send(model.setSoundModesPacket(switchingTo: target, from: current),
                          label: "switch \(round) to \(target.title)")
                try? await Task.sleep(for: .seconds(2))
                self.send(Packet.requestState, label: "Request State (2 s after switch \(round))")
                try? await Task.sleep(for: .milliseconds(500))
                if self.lastModes?.ambient == target {
                    stuck += 1
                    self.log("   round \(round): OK")
                } else {
                    self.log("   round \(round): FAILED, headphones say \(self.lastModes?.ambient.title ?? "?")")
                }
            }
            self.note("\(self.device?.name ?? "?"): \(stuck)/\(self.cycleCount) switches stuck "
                + "(\(self.stateAfterAck ? "with" : "without") a state request right after each ack)")
            self.closeChannel()
        }
    }

    private func trackModes(_ packet: Packet) {
        guard let model else { return }
        switch packet.command {
        case .state:
            if let modes = model.soundModes(inState: packet.body) {
                lastModes = modes
                log("   = state says \(modes.ambient.title)")
            }
        case .soundModesChanged:
            if let current = lastModes, let modes = model.applyingChange(packet.body, to: current) {
                lastModes = modes
                log("   = change push says \(modes.ambient.title)")
            }
        case .setSoundModes:
            log("   = acknowledged")
            if cycleCount > 0 && stateAfterAck {
                send(Packet.requestState, label: "Request State (right after ack)")
            }
        default:
            break
        }
    }

    private func send(_ packet: Packet, label: String) {
        guard let channel else { return }
        var bytes = packet.encoded()
        log("tx \(label): \(bytes.hexString)")
        let status = bytes.withUnsafeMutableBytes { buffer in
            channel.writeSync(buffer.baseAddress, length: UInt16(buffer.count))
        }
        if status != kIOReturnSuccess { log("writeSync failed: \(hex(status))") }
    }

    private func received(_ bytes: [UInt8]) {
        log("rx \(bytes.count) bytes: \(bytes.hexString)")
        for packet in parser.append(bytes) {
            log("   packet \(packet.command), \(packet.body.count)-byte body:")
            dump(packet.body)
            trackModes(packet)
            if packet.command == .state && !stateReceived {
                stateReceived = true
                note("\(device?.name ?? "?"): state reply has a \(packet.body.count)-byte body")
                if let extraPacket { sendExtraPacket(extraPacket) }
                if cycleCount > 0 { runCycle() }
            }
        }
        if parser.pendingByteCount > 0 { log("   (\(parser.pendingByteCount) bytes waiting for the rest of a packet)") }
    }

    private func sendExtraPacket(_ packet: Packet) {
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            self.send(packet, label: "--send packet")
            try? await Task.sleep(for: .milliseconds(700))
            self.send(Packet.requestState, label: "Request State (after --send)")
        }
    }

    private func closeChannel() {
        guard let channel else { return }
        self.channel = nil
        // Only the RFCOMM channel is closed; the audio connection stays up.
        channel.setDelegate(nil)
        channel.close()
        log("Channel closed.")
        probeNext()
    }

    // MARK: Output

    private func finish(reason: String) {
        log("")
        log("== Summary ==")
        summary.forEach { log("  " + $0) }
        log(reason)
        exit(0)
    }

    private func note(_ text: String) {
        summary.append(text)
        log(text)
    }

    private func log(_ text: String) {
        let elapsed = String(format: "%7.3f", Date().timeIntervalSince(started))
        print("[\(elapsed)] \(text)")
    }

    private func dump(_ bytes: [UInt8]) {
        for offset in stride(from: 0, to: bytes.count, by: 16) {
            let row = bytes[offset..<min(offset + 16, bytes.count)]
            let ascii = String(row.map { (0x20..<0x7F).contains($0) ? Character(UnicodeScalar($0)) : "." })
            let hexPart = row.hexString.padding(toLength: 47, withPad: " ", startingAt: 0)
            log(String(format: "     %04d  ", offset) + hexPart + "  |\(ascii)|")
        }
    }

    private func hex(_ status: IOReturn) -> String {
        "0x" + String(UInt32(bitPattern: status), radix: 16)
    }
}

extension Probe: @preconcurrency IOBluetoothRFCOMMChannelDelegate {
    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        guard rfcommChannel == channel else { return }
        if error == kIOReturnSuccess {
            channelOpened()
        } else {
            note("\(device?.name ?? "?"): RFCOMM open failed with \(hex(error))")
            channel = nil
            probeNext()
        }
    }

    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        guard rfcommChannel == channel, let dataPointer else { return }
        received(Array(UnsafeRawBufferPointer(start: dataPointer, count: dataLength)))
    }

    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        guard rfcommChannel == channel else { return }
        log("Channel closed by the device.")
        channel = nil
        probeNext()
    }
}

func argument(after flag: String) -> String? {
    let args = CommandLine.arguments
    guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
    return args[index + 1]
}

let modeArguments: [String: AmbientSoundMode] = [
    "nc": .noiseCanceling, "transparency": .transparency, "normal": .normal,
]
let targetModes = (argument(after: "--set") ?? "")
    .split(separator: ",")
    .map { modeArguments[$0.lowercased()] }
if targetModes.contains(where: { $0 == nil }) {
    print("--set takes one or more of \(modeArguments.keys.sorted().joined(separator: ", ")), comma-separated")
    exit(1)
}
var extraPacket: Packet?
if let text = argument(after: "--send") {
    guard let raw = bytes(fromHex: text), raw.count >= 2 else {
        print("--send takes hex: two command bytes, then the body")
        exit(1)
    }
    extraPacket = Packet(.outbound, Command(raw[0], raw[1]), body: Array(raw.dropFirst(2)))
}
let probe = Probe(
    listenSeconds: argument(after: "--listen").flatMap(Double.init) ?? 5,
    deviceFilter: argument(after: "--device"),
    targetModes: targetModes.compactMap { $0 },
    extraPacket: extraPacket,
    cycleCount: argument(after: "--cycle").flatMap(Int.init) ?? 0,
    stateAfterAck: CommandLine.arguments.contains("--state-after-ack")
)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
probe.start()
app.run()
