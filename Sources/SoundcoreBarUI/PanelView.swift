import SoundcoreKit
import SwiftUI

/// One connected pair, as the panel shows it.
public struct HeadphonesItem: Identifiable, Equatable {
    public enum State: Equatable {
        case connecting
        case ready(AmbientSoundMode)
        /// Connected but not usable; the message says why.
        case problem(String)
    }

    public let id: String
    public let name: String
    public let formFactor: FormFactor
    public let state: State

    public init(id: String, name: String, formFactor: FormFactor, state: State) {
        self.id = id
        self.name = name
        self.formFactor = formFactor
        self.state = state
    }
}

/// The menu bar panel: a section per connected pair with its three modes, then the icon picker
/// and Quit.
public struct PanelView: View {
    let items: [HeadphonesItem]
    let bluetoothDenied: Bool
    let onSelect: (HeadphonesItem.ID, AmbientSoundMode) -> Void
    let onOpenBluetoothSettings: () -> Void
    let onQuit: () -> Void
    // `@State` is a compiler macro in the macOS 27 SDK and the Command Line Tools ship without its
    // plugin, so view state is declared with the `State` type directly; SwiftUI treats it the same.
    private let showsIconPicker: State<Bool>

    public init(
        items: [HeadphonesItem],
        bluetoothDenied: Bool,
        showsIconPicker: Bool = false,
        onSelect: @escaping (HeadphonesItem.ID, AmbientSoundMode) -> Void,
        onOpenBluetoothSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.items = items
        self.bluetoothDenied = bluetoothDenied
        self.showsIconPicker = State(initialValue: showsIconPicker)
        self.onSelect = onSelect
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
                    HeadphonesSection(item: item) { onSelect(item.id, $0) }
                }
            }
            Divider()
            IconPicker(isExpanded: showsIconPicker.projectedValue)
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
        .padding(16)
        .frame(width: 300)
    }

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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: item.formFactor == .earbuds ? "earbuds" : "headphones")
                    .foregroundStyle(.secondary)
                Text(item.name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                if item.state == .connecting {
                    ProgressView().controlSize(.small)
                }
            }
            switch item.state {
            case .ready(let mode):
                ModeButtons(current: mode, onSelect: onSelect)
            case .connecting:
                ModeButtons(current: nil, onSelect: nil)
            case .problem(let message):
                ModeButtons(current: nil, onSelect: nil)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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
                    VStack(spacing: 6) {
                        Button { onSelect?(mode) } label: {
                            Image(systemName: mode.symbolName)
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 30, height: 30)
                        }
                        .modifier(GlassCircleButtonStyle(isProminent: mode == current))
                        .controlSize(.large)
                        // The plain and tinted styles size themselves differently; a fixed frame
                        // keeps the labels in line.
                        .frame(width: 52, height: 52)
                        .disabled(onSelect == nil)
                        .accessibilityLabel(mode.title)
                        Text(mode.title)
                            .font(.caption)
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
