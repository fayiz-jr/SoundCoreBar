// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 fayiz-jr

/// Soundcore R50i NC (A3959), earbuds. Bluetooth name contains "R50i", renamed ones too
/// (e.g. "🐰soundcore R50i🦋").
///
/// State body (91 bytes): TWS status (2), battery (4), firmware (10), serial (16), equalizer (12),
/// unknown (11), buttons (8), mode cycle (1), sound modes (7) at offset 64, then 20 more bytes.
/// Sound modes: [ambient, manual/adaptive NC levels, byte that stays 00 in every mode, NC mode,
/// wind noise, adaptive sensitivity, multi-scene mode].
/// Its change push carries the whole 7-byte block in the same layout.
public struct SoundcoreR50iNC: HeadphoneModel {
    public init() {}
    public let modelNumber = "A3959"
    public let formFactor = FormFactor.earbuds
    public let nameKeyword = "R50i"
    public let stateBodyLength = 91
    public let soundModesRange = 64..<71

    public func applyingChange(_ push: [UInt8], to current: SoundModes) -> SoundModes? {
        guard push.count == current.bytes.count else { return nil }
        return SoundModes(push)
    }
}
