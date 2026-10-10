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
        /// Headphones this app does not know how to control; the setup assistant can learn them.
        case unsupported(String)
        /// The setup assistant is learning them.
        case settingUp
    }

    public enum Badge: Equatable {
        /// A model that has not been tried on real headphones yet.
        case beta
        /// A model learned by the setup assistant.
        case learned
    }

    public let id: String
    public let name: String
    /// Nil until the model is known.
    public let formFactor: FormFactor?
    public let badge: Badge?
    public let state: State

    public init(id: String, name: String, formFactor: FormFactor?, badge: Badge? = nil, state: State) {
        self.id = id
        self.name = name
        self.formFactor = formFactor
        self.badge = badge
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
    let onSetUp: (HeadphonesItem.ID) -> Void
    let onForget: (HeadphonesItem.ID) -> Void
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
        onSetUp: @escaping (HeadphonesItem.ID) -> Void = { _ in },
        onForget: @escaping (HeadphonesItem.ID) -> Void = { _ in },
        onOpenBluetoothSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.items = items
        self.bluetoothDenied = bluetoothDenied
        self.showsIconPicker = showsIconPicker
        self.onSelect = onSelect
        self.onRetry = onRetry
        self.onSetUp = onSetUp
        self.onForget = onForget
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
                    HeadphonesSection(
                        item: item,
                        onSelect: { onSelect(item.id, $0) },
                        onRetry: { onRetry(item.id) },
                        onSetUp: { onSetUp(item.id) },
                        onForget: { onForget(item.id) }
                    )
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
    let onSetUp: () -> Void
    let onForget: () -> Void
    /// Whether the "forget these headphones?" row is showing. (See IconPicker for why `State` is
    /// used directly.)
    private let confirmsForget = State(initialValue: false)

    init(item: HeadphonesItem, onSelect: @escaping (AmbientSoundMode) -> Void, onRetry: @escaping () -> Void,
         onSetUp: @escaping () -> Void, onForget: @escaping () -> Void) {
        self.item = item
        self.onSelect = onSelect
        self.onRetry = onRetry
        self.onSetUp = onSetUp
        self.onForget = onForget
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: item.formFactor == .earbuds ? "earbuds" : "headphones")
                    .foregroundStyle(.secondary)
                Text(item.name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                switch item.badge {
                case .beta: BetaBadge()
                case .learned:
                    Button {
                        withAnimation(.smooth) { confirmsForget.wrappedValue.toggle() }
                    } label: {
                        BadgeLabel(text: "Learned")
                    }
                    .buttonStyle(.plain)
                    .help("Set up with the SoundcoreBar setup assistant. Click to forget.")
                case nil: EmptyView()
                }
                Spacer(minLength: 0)
                if item.state == .connecting || item.state == .settingUp {
                    ProgressView().controlSize(.small)
                }
            }
            if confirmsForget.wrappedValue, item.badge == .learned {
                HStack(alignment: .firstTextBaseline) {
                    note("Forget these headphones? You can set them up again.")
                    Spacer(minLength: 8)
                    Button("Keep") {
                        withAnimation(.smooth) { confirmsForget.wrappedValue = false }
                    }
                    .controlSize(.small)
                    Button("Forget", role: .destructive) {
                        confirmsForget.wrappedValue = false
                        onForget()
                    }
                    .controlSize(.small)
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
                HStack(alignment: .firstTextBaseline) {
                    note(message)
                    Spacer(minLength: 8)
                    Button("Set Up…", action: onSetUp)
                        .controlSize(.small)
                        .help("Teach SoundcoreBar these headphones")
                }
            case .settingUp:
                ModeButtons(current: nil, onSelect: nil)
                note("Setting up in the SoundcoreBar Setup window.")
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
        BadgeLabel(text: "Beta")
            .help("SoundcoreBar has not been tried with this model yet. If something looks wrong, please open an issue on GitHub.")
    }
}

private struct BadgeLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.secondary.opacity(0.15), in: .capsule)
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
