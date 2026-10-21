// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 fayiz-jr

extension HeadphoneModels {
    /// Every Soundcore model with noise control that OpenSCQ30 describes
    /// (https://github.com/Oppzippy/OpenSCQ30, lib/src/devices/soundcore). Offsets were worked out
    /// from its state parsers and checked against the real packets in its tests
    /// (Tests/SoundcoreKitTests/OpenSCQ30Fixtures.swift).
    ///
    /// Older models (the first group) report their mode in a 4-byte block and push only the mode
    /// when it changes; newer ones push their whole block. Several older ones have no serial number
    /// in their state reply, so they are recognised by name instead.
    public static let builtIn: [HeadphoneModel] = [
        // Over-ear, older format.
        HeadphoneModel(
            // Firmware 00.26 reads a 6-byte block, not OpenSCQ30's 4: a 4-byte set stored the
            // packet's checksum in byte 4. Its push is [mode, ff ff ff ff ff].
            modelNumbers: ["A3004"], name: "Q20i", nameKeywords: ["Q20i"], formFactor: .overEar,
            serialOffset: 7, soundModesOffset: 35, soundModesLength: 6, pushCarriesBlock: false,
            verified: true
        ),
        HeadphoneModel(
            modelNumbers: ["A3027", "A3030"], name: "Life Q35 / Life Tune Pro",
            nameKeywords: ["Life Q35", "Life Tune Pro"], formFactor: .overEar,
            serialOffset: 44, soundModesOffset: 35, soundModesLength: 4, pushCarriesBlock: false
        ),
        HeadphoneModel(
            modelNumbers: ["A3028", "A3029"], name: "Life Q30 / Life Tune",
            nameKeywords: ["Q30", "Life Tune"], formFactor: .overEar,
            serialOffset: 44, soundModesOffset: 35, soundModesLength: 4, pushCarriesBlock: false
        ),
        HeadphoneModel(
            modelNumbers: ["A3031"], name: "Vortex", nameKeywords: ["Vortex"], formFactor: .overEar,
            serialOffset: nil, soundModesOffset: 36, soundModesLength: 4, pushCarriesBlock: false
        ),

        // Earbuds, older format.
        HeadphoneModel(
            modelNumbers: ["A3930"], name: "Liberty 2 Pro+", nameKeywords: ["Liberty 2 Pro+"], formFactor: .earbuds,
            serialOffset: nil, soundModesOffset: 77, soundModesLength: 4, pushCarriesBlock: false
        ),
        HeadphoneModel(
            modelNumbers: ["A3931", "A3935"], name: "Life Dot 2 NC / Life A2 NC",
            nameKeywords: ["Life Dot 2 NC", "Life A2 NC"], formFactor: .earbuds,
            serialOffset: nil, soundModesOffset: 36, soundModesLength: 4, pushCarriesBlock: false
        ),
        HeadphoneModel(
            modelNumbers: ["A3933", "A3939"], name: "Life Note 3 / Life P3",
            nameKeywords: ["Life Note 3", "Life P3"], formFactor: .earbuds,
            serialOffset: nil, soundModesOffset: 116, soundModesLength: 4, pushCarriesBlock: false
        ),
        HeadphoneModel(
            modelNumbers: ["A3951"], name: "Liberty Air 2 Pro", nameKeywords: ["Liberty Air 2 Pro"], formFactor: .earbuds,
            serialOffset: nil, soundModesOffset: 77, soundModesLength: 4, pushCarriesBlock: false
        ),

        // Over-ear, newer format.
        HeadphoneModel(
            modelNumbers: ["A3035"], name: "Space One", nameKeywords: ["Space One"], formFactor: .overEar,
            serialOffset: 7, soundModesOffset: 69, soundModesLength: 6, pushCarriesBlock: true
        ),
        HeadphoneModel(
            modelNumbers: ["A3040"], name: "Space Q45", nameKeywords: ["Space Q45"], formFactor: .overEar,
            serialOffset: 7, soundModesOffset: 49, soundModesLength: 6, pushCarriesBlock: true
        ),
        HeadphoneModel(
            modelNumbers: ["A3062"], name: "Space One Pro", nameKeywords: ["Space One Pro"], formFactor: .overEar,
            serialOffset: 7, soundModesOffset: 69, soundModesLength: 6, pushCarriesBlock: true
        ),

        // Earbuds, newer format.
        HeadphoneModel(
            modelNumbers: ["A3936"], name: "Space A40", nameKeywords: ["Space A40"], formFactor: .earbuds,
            serialOffset: 16, soundModesOffset: 117, soundModesLength: 6, pushCarriesBlock: true
        ),
        HeadphoneModel(
            modelNumbers: ["A3947"], name: "Liberty 4 NC", nameKeywords: ["Liberty 4 NC"], formFactor: .earbuds,
            serialOffset: 16, soundModesOffset: 126, soundModesLength: 7, pushCarriesBlock: true
        ),
        HeadphoneModel(
            modelNumbers: ["A3952"], name: "Liberty 3 Pro", nameKeywords: ["Liberty 3 Pro"], formFactor: .earbuds,
            serialOffset: 16, soundModesOffset: 121, soundModesLength: 6, pushCarriesBlock: true
        ),
        HeadphoneModel(
            modelNumbers: ["A3954"], name: "Liberty 4 Pro", nameKeywords: ["Liberty 4 Pro"], formFactor: .earbuds,
            serialOffset: 16, soundModesOffset: 125, soundModesLength: 4, pushCarriesBlock: true,
            extraModes: [3]  // airplane mode
        ),
        HeadphoneModel(
            modelNumbers: ["A3955"], name: "P40i", nameKeywords: ["P40i"], formFactor: .earbuds,
            serialOffset: 16, soundModesOffset: 119, soundModesLength: 7, pushCarriesBlock: true
        ),
        HeadphoneModel(
            modelNumbers: ["A3957"], name: "Liberty 5", nameKeywords: ["Liberty 5"], formFactor: .earbuds,
            serialOffset: 16, soundModesOffset: 119, soundModesLength: 7, pushCarriesBlock: true
        ),
        HeadphoneModel(
            // Byte 2 of the block stays 00 in every mode. Asking for the state before a switch has
            // reached the other bud undoes it; see SoundcoreConnection.settleTimeout.
            modelNumbers: ["A3959"], name: "P30i / R50i NC", nameKeywords: ["P30i", "R50i"], formFactor: .earbuds,
            serialOffset: 16, soundModesOffset: 64, soundModesLength: 7, pushCarriesBlock: true,
            verified: true
        ),
        HeadphoneModel(
            modelNumbers: ["A3968"], name: "Sport X20", nameKeywords: ["Sport X20"], formFactor: .earbuds,
            serialOffset: 16, soundModesOffset: 117, soundModesLength: 6, pushCarriesBlock: true
        ),
        HeadphoneModel(
            modelNumbers: ["D1202"], name: "P31i / R60i NC", nameKeywords: ["P31i", "R60i"], formFactor: .earbuds,
            serialOffset: 16, soundModesOffset: 119, soundModesLength: 8, pushCarriesBlock: true
        ),

        // Earbuds, tagged format. Not in OpenSCQ30; worked out from reports in SoundcoreBar issue #1.
        HeadphoneModel(
            // Serial numbers start 1203. The block is entries 24, 25 and 26: [mode, 00, 00, 05, 01,
            // 00, 00], the same 7 bytes as its change notices. Its state reply kept reporting the
            // mode it connected in while the notices showed every switch, so it is never re-read.
            modelNumbers: ["1203"], name: "Liberty 5 Pro", nameKeywords: ["Liberty 5 Pro"], formFactor: .earbuds,
            serialOffset: nil, soundModesOffset: 0, soundModesLength: 7, pushCarriesBlock: true,
            soundModesTags: [0x24, 0x25, 0x26], serialTag: 0x07, stateUpdatesLive: false
        ),
    ]
}
