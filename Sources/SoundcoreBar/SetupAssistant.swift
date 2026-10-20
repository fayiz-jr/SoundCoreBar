// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 fayiz-jr

import AppKit
import SoundcoreBarUI
import SoundcoreBluetooth
import SoundcoreKit
import SwiftUI

/// Teaches SoundcoreBar one pair of unknown headphones (see `ModelLearner`):
///
/// 1. The user puts the headphones in each mode with their own button; the state is read after
///    each, and the button's change notices are collected.
/// 2. The learner finds the block that holds the mode.
/// 3. One test switch: the block is sent back with another mode, and the state read again must show
///    that mode with nothing after the block changed. The user confirms they heard it, and the
///    original block is sent back.
/// 4. The model is saved, and the headphones are recognised as it from then on.
///
/// Until step 3 nothing but state requests is sent.
final class SetupAssistant: ObservableObject {
    @Published private(set) var state: SetupState
    var onFinish: (() -> Void)?

    private let connection: SoundcoreConnection
    private let onSave: (HeadphoneModel) -> Void
    private var learner = ModelLearner()
    private var latestState: [UInt8]?
    private var finding: Result<ModelLearner.Finding, ModelLearner.Problem>?
    private var testPassed: Bool?
    /// The block as it was before the test switch, sent back afterwards.
    private var originalBlock: [UInt8]?
    private var connectTimeout: Task<Void, Never>?
    private var isFinished = false

    private static let connectTimeLimit: Duration = .seconds(20)
    private static let issuesURL = URL(string: "https://github.com/fayiz-jr/SoundCoreBar/issues/new")!

    init(connection: SoundcoreConnection, onSave: @escaping (HeadphoneModel) -> Void) {
        self.connection = connection
        self.onSave = onSave
        state = SetupState(deviceName: connection.name)
    }

    var actions: SetupActions {
        SetupActions(
            start: { [weak self] in self?.start() },
            setFormFactor: { [weak self] in self?.state.formFactor = $0 },
            record: { [weak self] in self?.record($0) },
            skip: { [weak self] in self?.skip($0) },
            test: { [weak self] in self?.test() },
            answer: { [weak self] in self?.answer($0) },
            copyReport: { [weak self] in self?.copyReport() },
            openIssues: { NSWorkspace.shared.open(Self.issuesURL) },
            close: { [weak self] in self?.onFinish?() }
        )
    }

    /// Gives the headphones back; called when the window closes.
    func close() {
        connectTimeout?.cancel()
        guard !isFinished else { return }
        isFinished = true
        connection.endLearning(adding: nil)
    }

    /// Called when the connection's status changes or the headphones disconnect.
    func connectionChanged(isConnected: Bool) {
        guard !isFinished else { return }
        let lost = !isConnected || {
            if case .failed = connection.status { return true }
            return false
        }()
        switch state.step {
        case .connecting, .record, .reading, .found, .testing, .confirm:
            if lost { fail("Lost the connection to the headphones.") }
        case .intro, .done, .failed:
            break
        }
    }

    // MARK: Steps

    private func start() {
        learner = ModelLearner()
        latestState = nil
        finding = nil
        testPassed = nil
        originalBlock = nil
        state.recorded = []
        state.skipped = []
        state.noticesSeen = 0
        state.report = nil
        state.step = .connecting
        connection.onLearningPacket = { [weak self] packet in self?.received(packet) }
        if connection.isLearning {
            // Starting over: the channel is still open.
            connection.learningReadState { [weak self] answered in
                guard let self, self.state.step == .connecting else { return }
                answered ? self.advance() : self.fail("The headphones stopped answering.")
            }
        } else {
            // Opening the channel reads the state; its arrival moves on (see `received`).
            connection.beginLearning()
        }
        connectTimeout?.cancel()
        connectTimeout = Task { [weak self] in
            try? await Task.sleep(for: Self.connectTimeLimit)
            guard !Task.isCancelled, let self, self.state.step == .connecting else { return }
            self.fail("Couldn’t connect to the headphones. Another app may be using their controls.")
        }
    }

    private func received(_ packet: Packet) {
        switch packet.command {
        case .state:
            latestState = packet.body
            if state.step == .connecting { advance() }
        case .soundModesChanged:
            // Only the button presses asked for are evidence; the test switch's notices are not.
            switch state.step {
            case .connecting, .record, .reading:
                learner.record(notice: packet.body)
                state.noticesSeen = learner.notices.count
            default:
                break
            }
        case .setSoundModes:
            break  // the acknowledgement of a test switch
        default:
            // Unknown messages, perhaps a newer model's notices: kept for the report.
            switch state.step {
            case .connecting, .record, .reading:
                learner.record(otherMessage: packet.command, body: packet.body)
            default:
                break
            }
        }
    }

    private func record(_ mode: AmbientSoundMode) {
        guard state.step == .record(mode) else { return }
        state.step = .reading(mode)
        connection.learningReadState { [weak self] answered in
            guard let self, self.state.step == .reading(mode) else { return }
            guard answered, let latest = self.latestState else {
                return self.fail("The headphones stopped answering.")
            }
            self.learner.record(state: latest, as: mode)
            self.state.recorded.append(mode)
            self.advance()
        }
    }

    private func skip(_ mode: AmbientSoundMode) {
        guard state.step == .record(mode) else { return }
        state.skipped.append(mode)
        advance()
    }

    /// The next mode to record, or the analysis once all three are done.
    private func advance() {
        connectTimeout?.cancel()
        if let next = AmbientSoundMode.allCases.first(where: { !state.recorded.contains($0) && !state.skipped.contains($0) }) {
            state.step = .record(next)
            return
        }
        let result = learner.analyse()
        finding = result
        state.report = report()
        switch result {
        case .success(let finding):
            guard let target = testTarget(for: finding) else {
                return fail("Couldn’t pick a mode to test with.")
            }
            let recognition = finding.serialOffset == nil
                ? "There’s no serial number in it, so they’ll be recognised by their Bluetooth name; keep it if you rename them."
                : "They’ll be recognised by their serial number, even if renamed."
            state.step = .found(
                location: "It’s byte \(finding.soundModesOffset) of their settings, in a \(finding.soundModesLength)-byte block. \(recognition)",
                target: target
            )
        case .failure(let problem):
            fail(Self.explanation(of: problem))
        }
    }

    /// A recorded mode other than the current one, preferring the one easiest to hear.
    private func testTarget(for finding: ModelLearner.Finding) -> AmbientSoundMode? {
        let current = latestState.flatMap { state in
            state.count > finding.soundModesOffset ? AmbientSoundMode(rawValue: state[finding.soundModesOffset]) : nil
        }
        return [AmbientSoundMode.transparency, .noiseCanceling, .normal].first {
            $0 != current && state.recorded.contains($0)
        }
    }

    private func test() {
        guard case .found(_, let target) = state.step, case .success(let finding) = finding else { return }
        let range = finding.soundModesOffset..<(finding.soundModesOffset + finding.soundModesLength)
        state.step = .testing("Reading the headphones’ settings…")
        connection.learningReadState { [weak self] answered in
            guard let self else { return }
            guard answered, let before = self.latestState, before.count >= range.upperBound,
                  AmbientSoundMode(rawValue: before[range.lowerBound]) != nil
            else { return self.fail("The headphones’ settings changed since they were read, so nothing was sent.") }
            let block = Array(before[range])
            self.originalBlock = block
            var switched = block
            switched[0] = target.rawValue
            self.state.step = .testing("Switching to \(target.title)…")
            self.connection.learningSendSoundModes(switched) { accepted in
                guard accepted else {
                    return self.fail("The headphones didn’t accept the switch, so nothing was changed.")
                }
                // Sent once the switch has settled.
                self.connection.learningReadState { answered in
                    guard answered, let after = self.latestState else {
                        return self.restore(then: "The headphones stopped answering after the switch.")
                    }
                    if let problem = Self.check(before: before, after: after, range: range, target: target) {
                        self.restore(then: problem)
                    } else {
                        self.state.step = .confirm(target)
                    }
                }
            }
        }
    }

    /// Whether the switch did what it should: the mode changed, and the bytes after the block did
    /// not (sending a block that is too short made the Q20i store other bytes there).
    private static func check(before: [UInt8], after: [UInt8], range: Range<Int>, target: AmbientSoundMode) -> String? {
        guard after.count == before.count else {
            return "The headphones’ settings changed shape after the switch, so SoundcoreBar won’t use what it found."
        }
        guard after[range.lowerBound] == target.rawValue else {
            return "The headphones accepted the switch but still report the old mode, so SoundcoreBar won’t use what it found."
        }
        let following = range.upperBound..<min(range.upperBound + 8, after.count)
        guard after[following] == before[following] else {
            return "The switch also changed other settings, so SoundcoreBar won’t use what it found."
        }
        return nil
    }

    private func answer(_ switched: Bool) {
        guard case .confirm = state.step else { return }
        testPassed = switched
        if switched {
            restore(then: nil)
        } else {
            restore(then: "Thanks for checking. SoundcoreBar won’t use what it found.")
        }
    }

    /// Sends the block from before the test, then saves the model, or fails with `problem`.
    private func restore(then problem: String?) {
        guard let originalBlock, case .success(let finding) = finding else {
            return fail(problem ?? "Something went wrong.")
        }
        let mode = AmbientSoundMode(rawValue: originalBlock[0])?.title ?? "the original mode"
        state.step = .testing("Switching back to \(mode)…")
        connection.learningSendSoundModes(originalBlock) { [weak self] accepted in
            guard let self else { return }
            self.connection.learningReadState { answered in
                let restored = accepted && answered
                    && self.latestState.map { $0.count > finding.soundModesOffset && $0[finding.soundModesOffset] == originalBlock[0] } == true
                if let problem {
                    self.fail(restored ? problem : problem + " The headphones may still be in the test mode; switch them with their button.")
                } else if restored {
                    self.save(finding)
                } else {
                    self.fail("The headphones didn’t switch back, so SoundcoreBar won’t use what it found. Switch them with their button.")
                }
            }
        }
    }

    private func save(_ finding: ModelLearner.Finding) {
        let model = learner.model(finding, deviceName: connection.name, formFactor: state.formFactor)
        state.report = report()
        isFinished = true
        onSave(model)
        connection.endLearning(adding: model)
        state.step = .done
    }

    private func fail(_ message: String) {
        connectTimeout?.cancel()
        state.report = learner.samples.isEmpty ? nil : report()
        state.step = .failed(message)
    }

    // MARK: Report

    private func report() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        return learner.report(deviceName: connection.name, finding: finding ?? learner.analyse(),
                              testPassed: testPassed, appVersion: version)
    }

    private func copyReport() {
        guard let report = state.report else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
    }

    private static func explanation(of problem: ModelLearner.Problem) -> String {
        switch problem {
        case .tooFewModes:
            "SoundcoreBar needs at least two modes to compare."
        case .noChangeNotice:
            "The headphones never announced a change. Switch them with their own button, not the Soundcore app, and try again."
        case .inconsistentNotices:
            "The headphones announced changes in different ways, so SoundcoreBar can’t tell how long their settings block is."
        case .noModeByte:
            "No setting followed the modes you chose. Make sure the headphones really were in each mode when you clicked, and try again."
        case .ambiguous:
            "Several settings changed together with the mode, so SoundcoreBar can’t tell which one to switch."
        }
    }
}

/// The assistant's window. Closing it at any step gives the headphones back.
final class SetupWindowController: NSObject, NSWindowDelegate {
    let assistant: SetupAssistant
    let address: String
    var onClose: (() -> Void)?
    private let window: NSWindow

    init(assistant: SetupAssistant, address: String) {
        self.assistant = assistant
        self.address = address
        let hosting = NSHostingController(rootView: SetupContent(assistant: assistant))
        hosting.sizingOptions = [.preferredContentSize]
        window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable]
        window.title = "SoundcoreBar Setup"
        window.isReleasedWhenClosed = false
        window.level = .floating
        super.init()
        window.delegate = self
        assistant.onFinish = { [weak self] in self?.window.close() }
    }

    func show() {
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        assistant.close()
        onClose?()
    }
}

private struct SetupContent: View {
    @ObservedObject var assistant: SetupAssistant

    var body: some View {
        SetupView(state: assistant.state, actions: assistant.actions)
    }
}
