// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 fayiz-jr

public enum AmbientSoundMode: UInt8, CaseIterable, Sendable {
    case noiseCanceling = 0
    case transparency = 1
    case normal = 2

    public var title: String {
        switch self {
        case .noiseCanceling: "Noise Cancelling"
        case .transparency: "Transparency"
        case .normal: "Normal"
        }
    }
}

/// A model's sound-modes block, byte for byte as the headphones last reported it. Byte 0 is the
/// mode; what the other bytes mean depends on the model, so they are kept as they are.
public struct SoundModes: Equatable, Sendable, CustomStringConvertible {
    public let bytes: [UInt8]

    /// Nil unless byte 0 is a mode: 0–2, or one of `extraModes` (the Liberty 4 Pro's airplane mode).
    public init?(_ bytes: [UInt8], extraModes: Set<UInt8> = []) {
        guard let first = bytes.first,
              AmbientSoundMode(rawValue: first) != nil || extraModes.contains(first)
        else { return nil }
        self.bytes = bytes
    }

    /// The mode, or nil for one this app does not switch to (such as airplane mode).
    public var ambient: AmbientSoundMode? {
        AmbientSoundMode(rawValue: bytes[0])
    }

    public func withAmbient(_ mode: AmbientSoundMode) -> SoundModes {
        withMode(byte: mode.rawValue)
    }

    func withMode(byte: UInt8) -> SoundModes {
        var bytes = bytes
        bytes[0] = byte
        return SoundModes(bytes, extraModes: [byte])!
    }

    public var description: String { "\(ambient?.title ?? "mode \(bytes[0])") [\(bytes.hexString)]" }
}
