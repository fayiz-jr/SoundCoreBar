// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 fayiz-jr

import Foundation
@preconcurrency import IOBluetooth
import OSLog
import SoundcoreKit

/// Keeps the control channel to one pair of headphones open, tracks its sound mode and switches it.
/// Which model the headphones are is worked out from their first state reply; headphones that
/// turn out not to be a known model are sent nothing more.
///
/// Main thread only: IOBluetooth delivers channel callbacks on the run loop that opened the channel.
/// Closing this connection closes only the RFCOMM channel; the audio connection is never touched.
public final class SoundcoreConnection: NSObject {
    public enum Status: Equatable {
        case connecting
        /// Nil while the headphones are in a mode this app does not switch to, such as airplane mode.
        case ready(AmbientSoundMode?)
        /// The headphones answered in a layout this app does not know; it will not send them anything.
        case unsupported(String)
        case failed(String)
        /// The setup assistant is learning the headphones; see `beginLearning()`.
        case settingUp
    }

    public let device: IOBluetoothDevice
    /// Known once the headphones have answered.
    public private(set) var model: HeadphoneModel?
    /// The state reply of headphones that are not a known model, for setting them up by hand.
    public private(set) var unrecognizedState: [UInt8]?
    public let address: String
    public private(set) var status: Status = .connecting {
        didSet { if status != oldValue { onChange?() } }
    }
    public var onChange: (() -> Void)?
    /// Receives one line per packet sent or received, for diagnostics.
    public var trace: ((String) -> Void)?

    /// OpenSCQ30 waits this long after each send before resending, then gives up.
    private static let resendWaits: [Duration] = [.milliseconds(500), .milliseconds(1000), .milliseconds(1500)]
    /// Quick retries right after connecting, then one every `slowRetryInterval`: another app (such
    /// as Vorssaint) may hold the controls, and they free up when it quits.
    private static let quickAttempts = 5
    private static let slowRetryInterval: Duration = .seconds(30)
    private static let unreachable = "Couldn’t connect. Another app may be using the headphones’ controls."
    private static let openTimeout: Duration = .seconds(10)
    /// How long to wait before opening the channel again after closing it, as between retries.
    private static let reopenDelay: Duration = .seconds(2)
    /// How long a switch may take to settle. Earbuds pass a switch on to the other bud, then push
    /// "sound modes changed" (within about 1 s when measured on the R50i NC). Sending anything else
    /// before that can undo it: a state request answered first made the R50i NC revert the switch
    /// in 7 of 10 tries. So nothing else is sent until the push arrives or this time passes.
    private static let settleTimeout: Duration = .seconds(2)

    private struct Request {
        let id: Int
        let packet: Packet
        let reply: Command
        let completion: (Packet?) -> Void
    }

    private var channel: IOBluetoothRFCOMMChannel?
    private var channelIsOpen = false
    private var parser = PacketStreamParser()
    private var soundModes: SoundModes?
    private var queue: [Request] = []
    private var inFlight: Request?
    private var nextRequestID = 0
    private var resendTask: Task<Void, Never>?
    private var reopenTask: Task<Void, Never>?
    private var openTimeoutTask: Task<Void, Never>?
    /// Set while a switch settles; see `settleTimeout`.
    private var settleTask: Task<Void, Never>?
    /// Connection attempts since the last state reply.
    private var attempts = 0
    private var awaitingSDP = false
    private var isClosed = false
    private var models: [HeadphoneModel]
    /// Set while the setup assistant has the channel.
    public private(set) var isLearning = false
    /// While learning, receives every state reply and change notice.
    public var onLearningPacket: ((Packet) -> Void)?
    private let log = Logger(subsystem: "com.fayizjr.SoundcoreBar", category: "connection")

    /// `models` are the models the headphones may turn out to be.
    public init(device: IOBluetoothDevice, models: [HeadphoneModel] = HeadphoneModels.builtIn) {
        self.device = device
        self.models = models
        self.address = device.addressString ?? ""
    }

    public var name: String { device.name ?? device.nameOrAddress ?? "Headphones" }

    public func start() {
        guard !isClosed, channel == nil else { return }
        attempts += 1
        // A background retry keeps showing the failure until it succeeds.
        if !isFailed { status = connectingStatus }
        if let service = SoundcoreServiceUUID.preferredService(in: device.rfcommServices) {
            open(service)
        } else if !awaitingSDP {
            // Nothing cached yet (e.g. first connection): ask the headphones for their services.
            awaitingSDP = true
            let result = device.performSDPQuery(self)
            if result != kIOReturnSuccess {
                awaitingSDP = false
                scheduleReopen(reason: "SDP query failed (\(result.hexCode))")
            }
        }
    }

    public func close() {
        isClosed = true
        reopenTask?.cancel()
        tearDownChannel()
    }

    /// Starts over at once instead of waiting for the next background retry.
    public func retryNow() {
        guard !isClosed, isFailed else { return }
        restart()
    }

    private var isFailed: Bool {
        if case .failed = status { return true }
        return false
    }

    private var connectingStatus: Status { isLearning ? .settingUp : .connecting }

    /// Starts over with another list of models: headphones not recognised before may be now, and
    /// headphones whose model was removed are not any more.
    public func useModels(_ models: [HeadphoneModel]) {
        self.models = models
        guard !isClosed, !isLearning else { return }
        let modelRemoved = model.map { !models.contains($0) } ?? false
        guard modelRemoved || unrecognizedState != nil else { return }
        restart()
    }

    private func restart() {
        reopenTask?.cancel()
        let closedOpenChannel = channel != nil
        tearDownChannel()
        model = nil
        unrecognizedState = nil
        attempts = 0
        status = connectingStatus
        guard closedOpenChannel else { return start() }
        // Reopening a channel straight after closing it timed out every time on the Q20i and the
        // R50i NC; the close needs a moment to finish.
        reopenTask = Task { [weak self] in
            try? await Task.sleep(for: Self.reopenDelay)
            guard !Task.isCancelled else { return }
            self?.start()
        }
    }

    /// Switches the ambient sound mode. The checkmark moves once the headphones acknowledge, and
    /// moves back if they then report that the switch did not stick.
    public func setMode(_ mode: AmbientSoundMode) {
        guard case .ready(let current) = status, current != mode, let model, let soundModes else { return }
        let packet = model.setSoundModesPacket(switchingTo: mode, from: soundModes)
        log.info("\(self.name, privacy: .public): switching to \(mode.title, privacy: .public)")
        // Only the latest choice matters: drop a switch that is still waiting to be sent.
        queue.removeAll { $0.packet.command == .setSoundModes }
        send(packet, expecting: .setSoundModes) { [weak self] reply in
            // Without an open channel the reconnect re-reads the state anyway.
            guard let self, self.channelIsOpen else { return }
            if reply != nil {
                self.apply(SoundModes(packet.body))
                self.beginSettling()
            } else {
                self.log.error("\(self.name, privacy: .public): no acknowledgement for set sound modes")
                self.requestState()
            }
        }
    }

    // MARK: Channel

    private func open(_ service: RFCOMMService) {
        log.info("\(self.name, privacy: .public): opening RFCOMM channel \(service.channelID) (attempt \(self.attempts))")
        var newChannel: IOBluetoothRFCOMMChannel?
        let result = device.openRFCOMMChannelAsync(&newChannel, withChannelID: service.channelID, delegate: self)
        guard result == kIOReturnSuccess, let newChannel else {
            scheduleReopen(reason: "openRFCOMMChannelAsync failed (\(result.hexCode))")
            return
        }
        channel = newChannel
        openTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.openTimeout)
            guard !Task.isCancelled, let self, !self.channelIsOpen else { return }
            self.scheduleReopen(reason: "RFCOMM open timed out")
        }
    }

    private func channelOpened() {
        openTimeoutTask?.cancel()
        openTimeoutTask = nil
        channelIsOpen = true
        parser.reset()
        requestState()
    }

    private func tearDownChannel() {
        resendTask?.cancel()
        resendTask = nil
        openTimeoutTask?.cancel()
        openTimeoutTask = nil
        settleTask?.cancel()
        settleTask = nil
        let pending = queue + (inFlight.map { [$0] } ?? [])
        queue.removeAll()
        inFlight = nil
        channelIsOpen = false
        // A new channel starts from a fresh state reply, never from a block read on an old one.
        soundModes = nil
        if let channel {
            self.channel = nil
            channel.setDelegate(nil)
            channel.close()
        }
        pending.forEach { $0.completion(nil) }
    }

    /// The channel can fail to open right after the headphones connect, while their profiles are
    /// still coming up, so retry a few times while they stay connected.
    private func scheduleReopen(reason: String) {
        tearDownChannel()
        guard !isClosed else { return }
        // Gone headphones are dropped by the monitor when their disconnect notice arrives.
        guard device.isConnected() else { status = .failed(Self.unreachable); return }
        let wait: Duration
        if attempts < Self.quickAttempts {
            log.notice("\(self.name, privacy: .public): \(reason, privacy: .public); retrying")
            if !isFailed { status = connectingStatus }
            wait = Self.reopenDelay
        } else {
            if !isFailed {
                log.error("\(self.name, privacy: .public): \(reason, privacy: .public); retrying every 30 s")
            }
            status = .failed(Self.unreachable)
            wait = Self.slowRetryInterval
        }
        reopenTask?.cancel()
        reopenTask = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            self?.start()
        }
    }

    // MARK: Requests

    private func requestState() {
        send(.requestState, expecting: .state) { [weak self] reply in
            guard let self, reply == nil, self.channelIsOpen else { return }
            if self.soundModes == nil {
                self.scheduleReopen(reason: "no reply to Request State")
            }
        }
    }

    /// Requests go out one at a time. Each is resent until its reply arrives, like OpenSCQ30 does.
    private func send(_ packet: Packet, expecting reply: Command, completion: @escaping (Packet?) -> Void) {
        nextRequestID += 1
        queue.append(Request(id: nextRequestID, packet: packet, reply: reply, completion: completion))
        sendNextRequest()
    }

    private func sendNextRequest() {
        guard channelIsOpen, inFlight == nil, settleTask == nil, !queue.isEmpty else { return }
        let request = queue.removeFirst()
        inFlight = request
        resendTask = Task { [weak self] in
            for wait in Self.resendWaits {
                guard let self, self.inFlight?.id == request.id else { return }
                self.write(request.packet)
                try? await Task.sleep(for: wait)
                guard !Task.isCancelled else { return }
            }
            self?.finishInFlight(with: nil)
        }
    }

    private func beginSettling() {
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: Self.settleTimeout)
            guard !Task.isCancelled else { return }
            // No push (the Q20i does not send one): read the state to confirm instead.
            self?.endSettling(confirm: true)
        }
    }

    private func endSettling(confirm: Bool) {
        guard settleTask != nil else { return }
        settleTask?.cancel()
        settleTask = nil
        // The setup assistant reads the state itself.
        if confirm, !isLearning {
            requestState()
        } else {
            sendNextRequest()
        }
    }

    private func finishInFlight(with reply: Packet?) {
        guard let request = inFlight else { return }
        inFlight = nil
        resendTask?.cancel()
        resendTask = nil
        request.completion(reply)
        sendNextRequest()
    }

    private func write(_ packet: Packet) {
        guard let channel else { return }
        var bytes = packet.encoded()
        trace?("tx \(bytes.hexString)")
        log.debug("\(self.name, privacy: .public) tx \(bytes.hexString, privacy: .public)")
        let result = bytes.withUnsafeMutableBytes { buffer in
            channel.writeSync(buffer.baseAddress, length: UInt16(buffer.count))
        }
        if result != kIOReturnSuccess {
            log.error("\(self.name, privacy: .public): write failed (\(result.hexCode, privacy: .public))")
        }
    }

    // MARK: Incoming

    private func received(_ bytes: [UInt8]) {
        trace?("rx \(bytes.hexString)")
        log.debug("\(self.name, privacy: .public) rx \(bytes.hexString, privacy: .public)")
        for packet in parser.append(bytes) {
            handle(packet)
        }
    }

    private func handle(_ packet: Packet) {
        if isLearning {
            // Everything, so that unknown models' own messages end up in the setup report.
            onLearningPacket?(packet)
            if packet.command == .soundModesChanged { endSettling(confirm: false) }
            if packet.command == inFlight?.reply { finishInFlight(with: packet) }
            return
        }
        switch packet.command {
        case .state:
            receivedState(packet.body)
        case .soundModesChanged:
            if let model, let soundModes, let updated = model.applyingChange(packet.body, to: soundModes) {
                apply(updated)
                endSettling(confirm: false)
            } else if soundModes != nil {
                log.notice("\(self.name, privacy: .public): unexpected change push \(packet.body.hexString, privacy: .public); re-reading state")
                endSettling(confirm: false)
                requestState()
            }
        default:
            break
        }
        if packet.command == inFlight?.reply {
            finishInFlight(with: packet)
        }
    }

    private func receivedState(_ state: [UInt8]) {
        if let model, let modes = model.soundModes(inState: state) {
            apply(modes)
            attempts = 0
            return
        }
        let previous = model
        model = HeadphoneModels.identify(state: state, deviceName: name, among: models)
        if let model, let modes = model.soundModes(inState: state) {
            log.info("\(self.name, privacy: .public): \(model.name, privacy: .public) (\(model.id, privacy: .public)\(model.verified ? "" : ", beta", privacy: .public))")
            unrecognizedState = nil
            apply(modes)
            attempts = 0
            return
        }
        // The reply holds the serial number, so only its length goes to the log.
        log.notice("\(self.name, privacy: .public): state of \(state.count) bytes matches no known model; leaving these headphones alone")
        unrecognizedState = state
        soundModes = nil
        status = .unsupported(previous == nil
            ? "This model isn’t supported yet."
            : "Unsupported firmware: the headphones’ settings have moved.")
        tearDownChannel()
    }

    private func apply(_ modes: SoundModes?) {
        guard let modes else { return }
        soundModes = modes
        status = .ready(modes.ambient)
    }
}

// MARK: - Setting up unknown headphones

extension SoundcoreConnection {
    /// Hands the channel to the setup assistant: state replies and change notices go to
    /// `onLearningPacket` instead of being matched to a model, and nothing is sent but what the
    /// assistant asks for.
    public func beginLearning() {
        guard !isClosed, !isLearning else { return }
        isLearning = true
        restart()
    }

    /// Reads the state; the reply reaches `onLearningPacket` before `completion` runs.
    public func learningReadState(completion: @escaping (Bool) -> Void) {
        guard isLearning else { return completion(false) }
        send(.requestState, expecting: .state) { completion($0 != nil) }
    }

    /// Sends a sound-modes block. As after any switch, nothing else is sent until the headphones
    /// report the change or `settleTimeout` passes, so a state read asked for now comes after that.
    public func learningSendSoundModes(_ block: [UInt8], completion: @escaping (Bool) -> Void) {
        guard isLearning else { return completion(false) }
        send(Packet(.outbound, .setSoundModes, body: block), expecting: .setSoundModes) { [weak self] reply in
            if reply != nil { self?.beginSettling() }
            completion(reply != nil)
        }
    }

    /// Gives the channel back. With a model, the headphones are recognised again from a fresh state
    /// reply; without one, they are left alone as before.
    public func endLearning(adding learned: HeadphoneModel?) {
        guard isLearning else { return }
        isLearning = false
        onLearningPacket = nil
        if let learned, !models.contains(learned) { models.append(learned) }
        restart()
    }
}

extension SoundcoreConnection: @preconcurrency IOBluetoothRFCOMMChannelDelegate {
    public func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        guard rfcommChannel == channel else { return }
        if error == kIOReturnSuccess {
            log.info("\(self.name, privacy: .public): channel open")
            channelOpened()
        } else {
            scheduleReopen(reason: "RFCOMM open failed (\(error.hexCode))")
        }
    }

    public func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        guard rfcommChannel == channel, let dataPointer else { return }
        received(Array(UnsafeRawBufferPointer(start: dataPointer, count: dataLength)))
    }

    public func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        guard rfcommChannel == channel else { return }
        scheduleReopen(reason: "channel closed by the headphones")
    }
}

extension SoundcoreConnection {
    /// Called by IOBluetooth when `performSDPQuery` finishes.
    @objc public func sdpQueryComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        guard awaitingSDP else { return }
        awaitingSDP = false
        if SoundcoreServiceUUID.preferredService(in: self.device.rfcommServices) != nil {
            start()
        } else {
            scheduleReopen(reason: "no Soundcore control service found (SDP status \(status.hexCode))")
        }
    }
}

extension IOReturn {
    var hexCode: String { "0x" + String(UInt32(bitPattern: self), radix: 16) }
}
