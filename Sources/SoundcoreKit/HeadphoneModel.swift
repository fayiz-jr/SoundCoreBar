public enum FormFactor: Sendable {
    case overEar
    case earbuds
}

/// How one Soundcore model lays out its sound modes. To support another model, add a small type
/// conforming to this protocol (see `Models/`) and list it in `HeadphoneModels.all`.
public protocol HeadphoneModel: Sendable {
    /// Soundcore model number, e.g. "A3004".
    var modelNumber: String { get }
    var formFactor: FormFactor { get }
    /// Text that appears in the model's Bluetooth device name, e.g. "Q20i".
    var nameKeyword: String { get }
    /// Length of the state (01 01) body this model sends. Replies of any other length are rejected,
    /// so a model with a similar name (e.g. the plain R50i) is never sent a block in the wrong layout.
    var stateBodyLength: Int { get }
    /// Where the sound-modes block sits in the state body. Its length is also the length of the
    /// set-sound-modes (06 81) body.
    var soundModesRange: Range<Int> { get }

    /// Applies a "sound modes changed" (06 01) push to the last known block.
    /// The default reads only the ambient sound mode from byte 0 of the push.
    func applyingChange(_ push: [UInt8], to current: SoundModes) -> SoundModes?
}

extension HeadphoneModel {
    public func matches(deviceName: String) -> Bool {
        deviceName.localizedCaseInsensitiveContains(nameKeyword)
    }

    /// The sound-modes block inside a state (01 01) body, or nil if the body is not this model's layout.
    public func soundModes(inState body: [UInt8]) -> SoundModes? {
        guard body.count == stateBodyLength else { return nil }
        return SoundModes(Array(body[soundModesRange]))
    }

    public func applyingChange(_ push: [UInt8], to current: SoundModes) -> SoundModes? {
        guard let first = push.first, let mode = AmbientSoundMode(rawValue: first) else { return nil }
        return current.withAmbient(mode)
    }

    /// The set-sound-modes packet that switches to `mode`: the last block the headphones sent,
    /// with only the ambient sound mode changed.
    public func setSoundModesPacket(switchingTo mode: AmbientSoundMode, from current: SoundModes) -> Packet {
        Packet(.outbound, .setSoundModes, body: current.withAmbient(mode).bytes)
    }
}

public enum HeadphoneModels {
    public static let all: [any HeadphoneModel] = [SoundcoreQ20i(), SoundcoreR50iNC()]

    public static func model(forDeviceName name: String) -> (any HeadphoneModel)? {
        all.first { $0.matches(deviceName: name) }
    }
}
