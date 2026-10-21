// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 fayiz-jr

import Foundation
import Testing
@testable import SoundcoreKit

@Suite struct Q20iTests {
    let model = builtIn("A3004")

    @Test func readsSoundModesFromRealState() {
        #expect(q20iState.count == 61)
        let modes = model.soundModes(inState: q20iState)
        #expect(modes?.bytes == hex("00 ff ff 01 01 ff"))
        #expect(modes?.ambient == .noiseCanceling)
    }

    @Test func switchingChangesOnlyTheAmbientByte() throws {
        let current = try #require(model.soundModes(inState: q20iState))
        #expect(model.setSoundModesPacket(switchingTo: .transparency, from: current).encoded()
            == hex("08 ee 00 00 00 06 81 10 00 01 ff ff 01 01 ff 8d"))
        // The packet that restored this state on the real headphones.
        #expect(model.setSoundModesPacket(switchingTo: .noiseCanceling, from: current.withAmbient(.normal)).encoded()
            == hex("08 ee 00 00 00 06 81 10 00 00 ff ff 01 01 ff 8c"))
    }

    @Test func appliesRealButtonPushes() throws {
        let pushes = inboundPackets(
            "09 ff 00 00 01 06 01 10 00 01 ff ff ff ff ff 1c",
            "09 ff 00 00 01 06 01 10 00 02 ff ff ff ff ff 1d",
            "09 ff 00 00 01 06 01 10 00 00 ff ff ff ff ff 1b"
        )
        #expect(pushes.map(\.command) == [.soundModesChanged, .soundModesChanged, .soundModesChanged])

        var modes = try #require(model.soundModes(inState: q20iState))
        var seen: [AmbientSoundMode?] = []
        for push in pushes {
            modes = try #require(model.applyingChange(push.body, to: modes))
            seen.append(modes.ambient)
            // The push pads with ff; the other bytes must keep the state's values.
            #expect(Array(modes.bytes.dropFirst()) == hex("ff ff 01 01 ff"))
        }
        #expect(seen == [.transparency, .normal, .noiseCanceling])
    }
}

@Suite struct R50iNCTests {
    let model = builtIn("A3959")

    @Test func readsSoundModesFromRealState() {
        #expect(r50iNCState().count == 91)
        let modes = model.soundModes(inState: r50iNCState())
        #expect(modes?.bytes == hex("02 35 00 01 01 ff 01"))
        #expect(modes?.ambient == .normal)
    }

    @Test func switchingChangesOnlyTheAmbientByte() throws {
        let current = try #require(model.soundModes(inState: r50iNCState()))
        #expect(model.setSoundModesPacket(switchingTo: .noiseCanceling, from: current).encoded()
            == hex("08 ee 00 00 00 06 81 11 00 00 35 00 01 01 ff 01 c5"))
    }

    @Test func appliesRealButtonPushes() throws {
        let pushes = inboundPackets(
            "09 ff 00 00 01 06 01 11 00 00 35 00 01 01 ff 01 58",
            "09 ff 00 00 01 06 01 11 00 01 35 00 01 01 ff 01 59",
            "09 ff 00 00 01 06 01 11 00 02 35 00 01 01 ff 01 5a"
        )
        var modes = try #require(model.soundModes(inState: r50iNCState()))
        var seen: [AmbientSoundMode?] = []
        for push in pushes {
            modes = try #require(model.applyingChange(push.body, to: modes))
            seen.append(modes.ambient)
            #expect(modes.bytes == push.body)
        }
        #expect(seen == [.noiseCanceling, .transparency, .normal])
    }

    @Test func rejectsPushOfUnexpectedLength() throws {
        let modes = try #require(model.soundModes(inState: r50iNCState()))
        #expect(model.applyingChange(hex("01 ff ff ff ff ff"), to: modes) == nil)
    }
}

@Suite struct IdentificationTests {
    @Test func recognisesRealHeadphonesBySerialNumber() {
        #expect(HeadphoneModels.identify(state: q20iState, deviceName: "soundcore Q20i")?.id == "A3004")
        #expect(HeadphoneModels.identify(state: r50iNCState(), deviceName: "🐰soundcore R50i🦋")?.id == "A3959")
        // Renamed headphones are still recognised.
        #expect(HeadphoneModels.identify(state: r50iNCState(), deviceName: "Bunny Buds")?.id == "A3959")
    }

    @Test func plainR50iIsNotMistakenForTheNoiseCancellingOne() {
        // The plain R50i (A3949, no noise cancelling) has a similar name; its serial gives it away.
        #expect(HeadphoneModels.identify(state: r50iNCState(serial: "3949"), deviceName: "soundcore R50i") == nil)
    }

    @Test func serialModelsAreNeverRecognisedByNameAlone() {
        #expect(HeadphoneModels.identify(state: r50iNCState(serial: "0000"), deviceName: "soundcore R50i NC") == nil)
    }

    @Test func rejectsStateOfAnotherLayout() {
        #expect(builtIn("A3004").soundModes(inState: r50iNCState()) == nil)
        #expect(builtIn("A3959").soundModes(inState: q20iState) == nil)
        // Too short to hold the block.
        #expect(builtIn("A3959").soundModes(inState: Array(r50iNCState().prefix(70))) == nil)
    }

    @Test func acceptsLongerStateFromNewerFirmware() {
        #expect(builtIn("A3959").soundModes(inState: r50iNCState() + [0, 0])?.ambient == .normal)
    }

    @Test func nameOnlyModelsNeedTheirWholeNameAndAPlausibleBlock() throws {
        let fixture = try #require(openSCQ30Fixtures.first { $0.model == "A3933" })
        #expect(HeadphoneModels.identify(state: fixture.state, deviceName: "Soundcore Life Note 3")?.id == "A3933/A3939")
        // The Life Note 3S is another model.
        #expect(HeadphoneModels.identify(state: fixture.state, deviceName: "Soundcore Life Note 3S") == nil)
        #expect(HeadphoneModels.identify(state: fixture.state, deviceName: "soundcore headphones") == nil)

        var garbled = fixture.state
        garbled[builtIn("A3933").soundModesOffset + 3] = 0x42  // custom noise cancelling above 10
        #expect(HeadphoneModels.identify(state: garbled, deviceName: "Soundcore Life Note 3") == nil)
    }

    @Test func candidatesAreSoundcoreByName() {
        #expect(HeadphoneModels.isCandidate(deviceName: "🐰soundcore R50i🦋"))
        #expect(HeadphoneModels.isCandidate(deviceName: "Life Note 3"))
        #expect(!HeadphoneModels.isCandidate(deviceName: "AirPods Pro"))
        #expect(!HeadphoneModels.isCandidate(deviceName: "Mi Silent Mouse"))
    }

    @Test func wholeWordMatching() {
        #expect(HeadphoneModel.name("Soundcore Liberty 2 Pro+", containsWord: "Liberty 2 Pro+"))
        #expect(!HeadphoneModel.name("Soundcore Liberty 2 Pro", containsWord: "Liberty 2 Pro+"))
        #expect(HeadphoneModel.name("my life p3 buds", containsWord: "Life P3"))
        #expect(!HeadphoneModel.name("Life P3i", containsWord: "Life P3"))
        #expect(HeadphoneModel.name("Life P3i / Life P3", containsWord: "Life P3"))
    }
}

/// OpenSCQ30's real packets and device-faker replies for every built-in model.
@Suite struct OpenSCQ30FixtureTests {
    /// Bluetooth names, from OpenSCQ30's device faker, for models recognised by name.
    static let names = [
        "A3930": "Soundcore Liberty 2 Pro+", "A3931": "Soundcore Life Dot 2 NC", "A3933": "Soundcore Life Note 3",
        "A3939": "Soundcore Life P3", "A3951": "Soundcore Liberty Air 2 Pro",
    ]

    @Test(arguments: openSCQ30Fixtures.map(\.model))
    func recognisesModel(_ modelNumber: String) throws {
        let fixture = try #require(openSCQ30Fixtures.first { $0.model == modelNumber })
        // Models with a serial number must be recognised without help from the name.
        let name = Self.names[modelNumber] ?? "Headphones"
        let model = try #require(HeadphoneModels.identify(state: fixture.state, deviceName: name))
        #expect(model.modelNumbers.contains(modelNumber))
        let modes = try #require(model.soundModes(inState: fixture.state))
        if let expected = fixture.expectedMode {
            #expect(modes.ambient == expected)
        }
        // Switching echoes the block back with only the mode changed.
        let packet = model.setSoundModesPacket(switchingTo: .transparency, from: modes)
        #expect(packet.body.count == model.soundModesLength)
        #expect(packet.body[0] == AmbientSoundMode.transparency.rawValue)
        #expect(Array(packet.body.dropFirst()) == Array(modes.bytes.dropFirst()))
    }

    /// The Q20i and the Liberty 5 Pro are covered by captures of their own. OpenSCQ30 has no packet
    /// for the Life Q35 or the Vortex: their offsets come from its parsers only.
    @Test func coversEveryBuiltInModel() {
        let withoutFixture: Set = ["A3004", "A3027/A3030", "A3031", "1203"]
        for model in HeadphoneModels.builtIn where !withoutFixture.contains(model.id) {
            #expect(model.modelNumbers.contains { number in openSCQ30Fixtures.contains { $0.model == number } },
                    "\(model.id) has no fixture")
        }
    }
}

@Suite struct ModelTableTests {
    @Test func modelNumbersAreUnique() {
        let numbers = HeadphoneModels.builtIn.flatMap(\.modelNumbers)
        #expect(Set(numbers).count == numbers.count)
    }

    @Test func onlyTestedModelsAreVerified() {
        #expect(HeadphoneModels.builtIn.filter(\.verified).map(\.id) == ["A3004", "A3959"])
    }

    @Test func airplaneModeIsShownAsNoMode() throws {
        let model = builtIn("A3954")
        let fixture = try #require(openSCQ30Fixtures.first { $0.model == "A3954" })
        var state = fixture.state
        state[model.soundModesOffset] = 3
        let modes = try #require(model.soundModes(inState: state))
        #expect(modes.ambient == nil)
        #expect(model.setSoundModesPacket(switchingTo: .normal, from: modes).body[0] == 2)
        // A push into airplane mode is followed too.
        let back = try #require(model.applyingChange([3] + modes.bytes.dropFirst(), to: modes.withAmbient(.normal)))
        #expect(back.ambient == nil)
    }

    @Test func modelsSurviveCoding() throws {
        let data = try JSONEncoder().encode(HeadphoneModels.builtIn)
        #expect(try JSONDecoder().decode([HeadphoneModel].self, from: data) == HeadphoneModels.builtIn)
    }

    @Test func soundModesRequireValidModeByte() {
        #expect(SoundModes([]) == nil)
        #expect(SoundModes([0x03, 0x00]) == nil)
        #expect(SoundModes([0x03, 0x00], extraModes: [3])?.ambient == nil)
        #expect(SoundModes([0x01])?.ambient == .transparency)
    }
}

@Suite struct Liberty5ProTests {
    let model = builtIn("1203")

    @Test func recognisedBySerialNumberInTaggedReply() {
        #expect(liberty5ProState.count == 371)
        #expect(HeadphoneModels.identify(state: liberty5ProState, deviceName: "Headphones")?.name == "Liberty 5 Pro")
        // The Liberty 5 (no Pro) is still told apart by its serial number.
        let liberty5 = openSCQ30Fixtures.first { $0.model == "A3957" }!
        #expect(HeadphoneModels.identify(state: liberty5.state, deviceName: "soundcore Liberty 5 Pro")?.id == "A3957")
    }

    @Test func readsTheBlockFromItsThreeEntries() {
        let modes = model.soundModes(inState: liberty5ProState)
        #expect(modes?.bytes == hex("02 00 00 05 01 00 00"))
        #expect(modes?.ambient == .normal)
    }

    @Test func findsEntriesWhenFirmwareChangesTheirPositions() {
        // Firmware 05.33 has a 3-byte entry 1b where 05.52 has 4 bytes, moving everything after it.
        var state = liberty5ProState
        let entry1b = TaggedState.entries(in: state)!.first { $0.tag == 0x1B }!
        state[entry1b.value.lowerBound - 1] = 3
        state.remove(at: entry1b.value.upperBound - 1)
        #expect(model.soundModes(inState: state)?.ambient == .normal)
    }

    @Test func followsItsButtonNoticesAndSwitchesWithTheSameBlock() throws {
        var modes = try #require(model.soundModes(inState: liberty5ProState))
        modes = try #require(model.applyingChange(hex("00 00 00 05 01 00 00"), to: modes))
        #expect(modes.ambient == .noiseCanceling)
        #expect(model.setSoundModesPacket(switchingTo: .transparency, from: modes).body == hex("01 00 00 05 01 00 00"))
    }

    @Test func itsStateIsNeverTrustedToFollowSwitches() {
        #expect(!model.stateFollowsChanges)
        #expect(HeadphoneModels.builtIn.filter { !$0.stateFollowsChanges }.map(\.name) == ["Liberty 5 Pro"])
    }
}
