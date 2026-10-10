// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 fayiz-jr

import SoundcoreKit
import SwiftUI

/// One connected pair, as the panel shows it.
public struct HeadphonesItem: Identifiable, Equatable {
    public enum State: Equatable {
        case connecting
        /// Nil while the headphones are in a mode not shown here, such as airplane mode.
        case ready(AmbientSoundMode?)
        /// Connected but not reachable for now; the message says why, and trying again may help.
        case problem(String)
        /// Headphones this app does not know how to control.
        case unsupported(String)
    }

    public let id: String
    public let name: String
    /// Nil until the model is known.
    public let formFactor: FormFactor?
    /// A model that has not been tested on real headphones yet.
    public let isBeta: Bool
    public let state: State

    public init(id: String, name: String, formFactor: FormFactor?, isBeta: Bool = false, state: State) {
        self.id = id
        self.name = name
        self.formFactor = formFactor
        self.isBeta = isBeta
        self.state = state
    }
}

/// The menu bar panel: a section per connected pair with its three modes, then the icon picker
/// and Quit.
public struct PanelView: View {
    let items: [HeadphonesItem]
    let bluetoothDenied: Bool
    let onSelect: (HeadphonesItem.ID, AmbientSoundMode) -> Void
    let onRetry: (HeadphonesItem.ID) -> Void
    let onOpenBluetoothSettings: () -> Void
    let onQuit: () -> Void
    @AppStorage(PanelPreferences.clearGlassKey) private var clearGlass = false
    let showsIconPicker: Binding<Bool>

    public init(
        items: [HeadphonesItem],
        bluetoothDenied: Bool,
        showsIconPicker: Binding<Bool>,
        onSelect: @escaping (HeadphonesItem.ID, AmbientSoundMode) -> Void,
        onRetry: @escaping (HeadphonesItem.ID) -> Void = { _ in },
        onOpenBluetoothSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.items = items
        self.bluetoothDenied = bluetoothDenied
        self.showsIconPicker = showsIconPicker
        self.onSelect = onSelect
        self.onRetry = onRetry
        self.onOpenBluetoothSettings = onOpenBluetoothSettings
        self.onQuit = onQuit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if bluetoothDenied {
                bluetoothDeniedSection
            } else if items.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Label("No Soundcore headphones connected", systemImage: "headphones")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    ModeButtons(current: nil, onSelect: nil)
                }
            } else {
                ForEach(items) { item in
                    if item.id != items.first?.id { Divider() }
                    HeadphonesSection(item: item, onSelect: { onSelect(item.id, $0) }, onRetry: { onRetry(item.id) })
                }
            }
            Divider()
            IconPicker(isExpanded: showsIconPicker)
            if #available(macOS 26, *) {
                Toggle("Clear Glass", isOn: $clearGlass)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            Divider()
            Button(action: onQuit) {
                HStack {
                    Text("Quit SoundcoreBar")
                    Spacer()
                    Text("⌘Q").foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
        }
        .padding(18)
        .frame(width: PanelView.width)
    }

    public static let width: CGFloat = 316

    private var bluetoothDeniedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Bluetooth access is off", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
            Text("SoundcoreBar needs Bluetooth to talk to your headphones. Turn it on, then reopen the app.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Bluetooth Settings…", action: onOpenBluetoothSettings)
        }
    }
}

struct HeadphonesSection: View {
    let item: HeadphonesItem
    let onSelect: (AmbientSoundMode) -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: item.formFactor == .earbuds ? "earbuds" : "headphones")
                    .foregroundStyle(.secondary)
                Text(item.name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if item.isBeta {
                    BetaBadge()
                }
                Spacer(minLength: 0)
                if item.state == .connecting {
                    ProgressView().controlSize(.small)
                }
            }
            switch item.state {
            case .ready(let mode):
                ModeButtons(current: mode, onSelect: onSelect)
                if mode == nil {
                    note("The headphones are in a mode not shown here, such as airplane mode.")
                }
            case .connecting:
                ModeButtons(current: nil, onSelect: nil)
            case .problem(let message):
                ModeButtons(current: nil, onSelect: nil)
                HStack(alignment: .firstTextBaseline) {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("Try Again", action: onRetry)
                        .controlSize(.small)
                }
            case .unsupported(let message):
                note(message)
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Marks models known only from OpenSCQ30's research, not yet tried with SoundcoreBar.
struct BetaBadge: View {
    var body: some View {
        Text("Beta")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.secondary.opacity(0.15), in: .capsule)
            .help("SoundcoreBar has not been tried with this model yet. If something looks wrong, please open an issue on GitHub.")
            .accessibilityLabel("Beta")
    }
}

/// The three modes as round glass buttons, the current one tinted. Disabled when `onSelect` is nil.
struct ModeButtons: View {
    let current: AmbientSoundMode?
    let onSelect: ((AmbientSoundMode) -> Void)?

    var body: some View {
        GlassGroup(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(AmbientSoundMode.allCases, id: \.self) { mode in
                    VStack(spacing: 7) {
                        GlassCircleButton(isSelected: mode == current, diameter: 50) {
                            onSelect?(mode)
                        } label: {
                            Image(systemName: mode.symbolName)
                                .font(.system(size: 18, weight: .semibold))
                        }
                        .disabled(onSelect == nil)
                        .opacity(onSelect == nil ? 0.45 : 1)
                        .accessibilityLabel(mode.title)
                        .accessibilityAddTraits(mode == current ? .isSelected : [])
                        Text(mode.title)
                            .font(.caption.weight(mode == current ? .semibold : .regular))
                            .foregroundStyle(mode == current ? .primary : .secondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .animation(.smooth, value: current)
    }
}

extension AmbientSoundMode {
    var symbolName: String {
        switch self {
        case .noiseCanceling: "waveform.slash"
        case .transparency: "ear.and.waveform"
        case .normal: "ear"
        }
    }
}
