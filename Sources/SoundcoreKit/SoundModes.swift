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

/// A model's sound-modes block, byte for byte as the headphones last reported it. Byte 0 is always
/// the ambient sound mode; what the other bytes mean depends on the model, so they are kept as-is.
public struct SoundModes: Equatable, Sendable, CustomStringConvertible {
    public let bytes: [UInt8]

    /// Nil unless byte 0 is a valid ambient sound mode.
    public init?(_ bytes: [UInt8]) {
        guard let first = bytes.first, AmbientSoundMode(rawValue: first) != nil else { return nil }
        self.bytes = bytes
    }

    public var ambient: AmbientSoundMode {
        AmbientSoundMode(rawValue: bytes[0])!
    }

    public func withAmbient(_ mode: AmbientSoundMode) -> SoundModes {
        var bytes = bytes
        bytes[0] = mode.rawValue
        return SoundModes(bytes)!
    }

    public var description: String { "\(ambient.title) [\(bytes.hexString)]" }
}
