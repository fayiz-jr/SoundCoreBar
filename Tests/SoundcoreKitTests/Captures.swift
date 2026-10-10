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
