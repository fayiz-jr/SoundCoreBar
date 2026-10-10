// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 fayiz-jr

/// Soundcore Q20i (A3004), over-ear. Bluetooth name "soundcore Q20i".
///
/// State body (61 bytes on firmware 00.26): battery (2), firmware (5), serial (16), equalizer (12),
/// sound modes (6) at offset 35, then 20 bytes not used here.
///
/// OpenSCQ30 treats the block as 4 bytes, [ambient, noise canceling mode, transparency mode,
/// custom noise canceling], but this firmware reads 6: after a 4-byte set it stored the packet's
/// checksum and a 00 in the two bytes that follow. So the whole 6-byte block is echoed back.
/// The headphones report ff for both sub-modes.
/// Its change push is [ambient, ff ff ff ff ff], so only byte 0 is read from it (the default).
public struct SoundcoreQ20i: HeadphoneModel {
    public init() {}
    public let modelNumber = "A3004"
    public let formFactor = FormFactor.overEar
    public let nameKeyword = "Q20i"
    public let stateBodyLength = 61
    public let soundModesRange = 35..<41
}
