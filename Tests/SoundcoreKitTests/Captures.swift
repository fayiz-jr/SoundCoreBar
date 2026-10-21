// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 fayiz-jr

@testable import SoundcoreKit

/// Builds bytes from hex fragments, so captures can be written field by field.
func hex(_ fragments: String...) -> [UInt8] {
    bytes(fromHex: fragments.joined(separator: " "))!
}

func inboundPackets(_ frames: String...) -> [Packet] {
    var parser = PacketStreamParser()
    return frames.flatMap { parser.append(hex($0)) }
}

/// A serial number field with the model's digits kept (that is how the model is recognised) and
/// the rest masked.
func maskedSerial(_ digits: String) -> String {
    (Array(digits.utf8) + Array(repeating: UInt8(ascii: "0"), count: 16 - digits.count)).hexString
}

func builtIn(_ modelNumber: String) -> HeadphoneModel {
    HeadphoneModels.builtIn.first { $0.modelNumbers.contains(modelNumber) }!
}

// Captured from a Q20i on firmware 00.26 with SoundcoreProbe.
let q20iState = hex(
    "03 00",                                // battery
    "30 30 2e 32 36",                       // firmware "00.26"
    maskedSerial("3004"),
    "fe fe 98 9d a1 99 a3 95 9e aa 00 00",  // equalizer
    "00 ff ff 01 01 ff",                    // sound modes: Noise Cancelling
    "01 31 ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff"
)

// Captured from an R50i NC on firmware 01.65 with SoundcoreProbe.
func r50iNCState(serial: String = "3959") -> [UInt8] {
    hex(
        "00 01 07 08 ff ff",                    // TWS status, battery
        "30 31 2e 36 35 30 31 2e 36 35",        // firmware "01.65" x2
        maskedSerial(serial),
        "fe fe 92 9a 9b 94 91 95 9b a2 00 00",  // equalizer
        "00 00 00 00 00 00 00 00 00 00 0a",     // unknown
        "f1 f0 62 66 f5 f3 44 44",              // buttons
        "37",                                   // mode cycle
        "02 35 00 01 01 ff 01",                 // sound modes: Normal
        "32 01 01 01 01 02 01 00 00 00 00 00 00 00 00 00 00 00 00 00"
    )
}

// Reported in SoundcoreBar issue #1 from a Liberty 5 Pro on firmware 05.52, in the tagged format, with
// its serial number masked and two Bluetooth addresses zeroed by SoundcoreBar 1.2.1. Its mode entries
// (24, 25, 26) say Normal.
let liberty5ProState = hex(
    "01 01 00 02 01 01 03 02 00 63 04 02 80 64 05 05 30 35 2e 35 32 06 05 30",
    "35 2e 35 32 07 11 31 32 30 33 30 30 30 30 30 30 30 30 30 30 30 30 00 08",
    "02 00 2b 09 05 30 31 2e 35 34 0a 01 32 0b 02 03 00 0c 20 00 00 00 00 00",
    "00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00",
    "00 00 00 0d 02 06 0f 0f 02 03 06 11 02 0f 0f 13 02 04 04 15 02 00 00 17",
    "02 01 01 0e 02 0f 0f 10 02 06 06 12 02 0f 0f 14 02 04 04 16 02 00 00 18",
    "02 01 01 19 02 01 02 2a 01 01 1a 01 ff 1b 04 08 01 10 20 1c 01 01 23 5c",
    "00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00",
    "00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00",
    "00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00",
    "00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 24 03 02 00",
    "00 25 02 05 01 26 02 00 00 27 03 00 5a 00 29 06 00 00 00 00 00 00 2c 03",
    "00 01 01 2e 01 63 30 01 02 31 01 00 32 02 00 00 33 06 00 00 00 00 00 00",
    "34 28 03 01 52 b8 fe 3f 00 28 88 45 aa f1 12 3f 01 00 00 40 bf 00 5c 17",
    "46 73 68 41 40 01 00 00 80 40 00 c0 6a 46 f2 d2 4d 3e 35 01 00 36 02 00",
    "01 44 01 00 3a 01 02 5c 02 00 00"
)
