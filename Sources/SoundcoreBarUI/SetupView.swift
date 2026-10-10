// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 fayiz-jr

import SoundcoreKit
import SwiftUI

/// What the setup assistant shows; the app's `SetupAssistant` moves it along.
public struct SetupState: Equatable {
    public enum Step: Equatable {
        case intro
        case connecting
        /// Waiting for the user to put the headphones in this mode.
        case record(AmbientSoundMode)
        /// Reading the state after the user said the headphones are in this mode.
        case reading(AmbientSoundMode)
        /// The mode was found; the test switch goes to `target`.
        case found(location: String, target: AmbientSoundMode)
        case testing(String)
        /// Asking whether the headphones switched to this mode.
        case confirm(AmbientSoundMode)
        case done
        case failed(String)
    }

    public var deviceName: String
    public var formFactor: FormFactor
    public var step: Step
    public var recorded: [AmbientSoundMode]
    public var skipped: [AmbientSoundMode]
    public var noticesSeen: Int
    /// The report to share in a GitHub issue, once there is something to report.
    public var report: String?

    public init(deviceName: String, formFactor: FormFactor = .earbuds, step: Step = .intro,
                recorded: [AmbientSoundMode] = [], skipped: [AmbientSoundMode] = [], noticesSeen: Int = 0,
                report: String? = nil) {
        self.deviceName = deviceName
        self.formFactor = formFactor
        self.step = step
        self.recorded = recorded
        self.skipped = skipped
        self.noticesSeen = noticesSeen
        self.report = report
    }
}

public struct SetupActions {
    public var start: () -> Void
    public var setFormFactor: (FormFactor) -> Void
    public var record: (AmbientSoundMode) -> Void
    public var skip: (AmbientSoundMode) -> Void
    public var test: () -> Void
    public var answer: (Bool) -> Void
    public var copyReport: () -> Void
    public var openIssues: () -> Void
    public var close: () -> Void

    public init(start: @escaping () -> Void, setFormFactor: @escaping (FormFactor) -> Void,
                record: @escaping (AmbientSoundMode) -> Void, skip: @escaping (AmbientSoundMode) -> Void,
                test: @escaping () -> Void, answer: @escaping (Bool) -> Void, copyReport: @escaping () -> Void,
                openIssues: @escaping () -> Void, close: @escaping () -> Void) {
        self.start = start
        self.setFormFactor = setFormFactor
        self.record = record
        self.skip = skip
        self.test = test
        self.answer = answer
        self.copyReport = copyReport
        self.openIssues = openIssues
        self.close = close
    }
}

/// The setup assistant for headphones SoundcoreBar does not know: the user switches them through
/// their modes with their own button, SoundcoreBar finds where the mode is kept, tries one switch
/// and saves the result.
public struct SetupView: View {
    let state: SetupState
    let actions: SetupActions

    public init(state: SetupState, actions: SetupActions) {
        self.state = state
        self.actions = actions
    }

    public static let width: CGFloat = 440

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            content
        }
        .padding(24)
        .frame(width: Self.width, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: state.formFactor == .earbuds ? "earbuds" : "headphones")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("Set Up Headphones")
                    .font(.title3.weight(.semibold))
                Text(state.deviceName)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch state.step {
        case .intro:
            intro
        case .connecting:
            progress("Connecting to the headphones…")
        case .record(let mode):
            record(mode, isReading: false)
        case .reading(let mode):
            record(mode, isReading: true)
        case .found(let location, let target):
            found(location: location, target: target)
        case .testing(let message):
            progress(message)
        case .confirm(let mode):
            confirm(mode)
        case .done:
            done
        case .failed(let message):
            failed(message)
        }
    }

    // MARK: Steps

    private var intro: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SoundcoreBar doesn’t know these headphones yet, but it can learn them in about a minute.")
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                numbered(1, "You switch the headphones through their modes with their own button while SoundcoreBar reads their settings.")
                numbered(2, "It finds the setting that holds the mode.")
                numbered(3, "It tries one switch, asks what you heard, and switches back.")
            }
            Text("Until that test it only reads from the headphones, and if anything looks wrong it sends them nothing.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Picker("These are", selection: Binding(get: { state.formFactor }, set: { actions.setFormFactor($0) })) {
                Text("Earbuds").tag(FormFactor.earbuds)
                Text("Over-ear").tag(FormFactor.overEar)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            buttons {
                Button("Cancel", action: actions.close)
                    .keyboardShortcut(.cancelAction)
                Button("Start", action: actions.start)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func record(_ mode: AmbientSoundMode, isReading: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ModeChecklist(recorded: state.recorded, skipped: state.skipped, current: mode)
            Text("Switch the headphones to \(Text(mode.title).bold()) with their own button, then click below.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Use the button on the headphones, not the Soundcore phone app: SoundcoreBar learns from the notice the button sends. Most models say the mode’s name or beep when it changes.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(state.noticesSeen == 1 ? "1 button press noticed" : "\(state.noticesSeen) button presses noticed")
                .font(.callout.monospacedDigit())
                .foregroundStyle(state.noticesSeen > 0 ? .primary : .secondary)
            buttons {
                Button("No Such Mode") { actions.skip(mode) }
                    .disabled(isReading)
                    .help("These headphones don’t have \(mode.title)")
                if isReading { ProgressView().controlSize(.small) }
                Button("It’s on \(mode.title)") { actions.record(mode) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isReading)
            }
        }
    }

    private func found(location: String, target: AmbientSoundMode) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Found the setting that holds the mode.", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .symbolRenderingMode(.multicolor)
            Text(location)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("To check it, SoundcoreBar will switch the headphones to \(Text(target.title).bold()), ask what you heard, then switch them back.")
                .fixedSize(horizontal: false, vertical: true)
            buttons {
                Button("Cancel", action: actions.close)
                    .keyboardShortcut(.cancelAction)
                Button("Try the Switch", action: actions.test)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func confirm(_ mode: AmbientSoundMode) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Did the headphones switch to \(Text(mode.title).bold())?")
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)
            Text("They report that they did. If you’re not sure, click No: nothing is saved, and they’re switched back either way.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            buttons {
                Button("No") { actions.answer(false) }
                Button("Yes") { actions.answer(true) }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("All set", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .symbolRenderingMode(.multicolor)
            Text("SoundcoreBar now controls \(state.deviceName). Switch it from the menu bar like any other pair.")
                .fixedSize(horizontal: false, vertical: true)
            share
            buttons {
                Button("Done", action: actions.close)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func failed(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Couldn’t set up these headphones", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .symbolRenderingMode(.multicolor)
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
            share
            buttons {
                Button("Close", action: actions.close)
                    .keyboardShortcut(.cancelAction)
                Button("Start Over", action: actions.start)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: Parts

    @ViewBuilder private var share: some View {
        if let report = state.report {
            Divider()
            Text("Help others with these headphones")
                .font(.headline)
            Text("Share this report in a GitHub issue so they can be added for everyone. It holds no serial number or Bluetooth address; check that the Bluetooth name is fine to share.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                Text(report)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(height: 130)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            HStack {
                Button("Copy Report", action: actions.copyReport)
                Button("Open GitHub Issues", action: actions.openIssues)
            }
        }
    }

    private func progress(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(message).foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
            buttons {
                Button("Cancel", action: actions.close)
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    private func numbered(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number).")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func buttons<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            content()
        }
        .controlSize(.large)
        .padding(.top, 4)
    }
}

/// The three modes with a mark for each: recorded, skipped, being recorded or still to come.
struct ModeChecklist: View {
    let recorded: [AmbientSoundMode]
    let skipped: [AmbientSoundMode]
    let current: AmbientSoundMode

    var body: some View {
        HStack(spacing: 18) {
            ForEach(AmbientSoundMode.allCases, id: \.self) { mode in
                HStack(spacing: 6) {
                    Image(systemName: symbol(for: mode))
                        .foregroundStyle(color(for: mode))
                    Text(mode.title)
                        .font(.callout.weight(mode == current ? .semibold : .regular))
                        .foregroundStyle(mode == current ? .primary : .secondary)
                        .strikethrough(skipped.contains(mode))
                }
            }
        }
    }

    private func symbol(for mode: AmbientSoundMode) -> String {
        if recorded.contains(mode) { return "checkmark.circle.fill" }
        if skipped.contains(mode) { return "minus.circle" }
        return mode == current ? "largecircle.fill.circle" : "circle"
    }

    private func color(for mode: AmbientSoundMode) -> Color {
        if recorded.contains(mode) { return .green }
        return mode == current ? .accentColor : .secondary
    }
}
