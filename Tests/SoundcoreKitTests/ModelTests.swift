import Testing
@testable import SoundcoreKit

/// Builds bytes from hex fragments, so captures can be written field by field.
private func hex(_ fragments: String...) -> [UInt8] {
    bytes(fromHex: fragments.joined(separator: " "))!
}

private func inboundPackets(_ frames: String...) -> [Packet] {
    var parser = PacketStreamParser()
    return frames.flatMap { parser.append(hex($0)) }
}

/// The serial number field, masked (it is not read by the app).
private let maskedSerial = Array(repeating: "30", count: 16).joined(separator: " ")

// Captured from a Q20i on firmware 00.26 with SoundcoreProbe.
private let q20iStateBody = hex(
    "03 00",                                // battery
    "30 30 2e 32 36",                       // firmware "00.26"
    maskedSerial,
    "fe fe 98 9d a1 99 a3 95 9e aa 00 00",  // equalizer
    "00 ff ff 01 01 ff",                    // sound modes: Noise Cancelling
    "01 31 ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff"
)

// Captured from an R50i NC on firmware 01.65 with SoundcoreProbe.
private let r50iNCStateBody = hex(
    "00 01 07 08 ff ff",                    // TWS status, battery
    "30 31 2e 36 35 30 31 2e 36 35",        // firmware "01.65" x2
    maskedSerial,
    "fe fe 92 9a 9b 94 91 95 9b a2 00 00",  // equalizer
    "00 00 00 00 00 00 00 00 00 00 0a",     // unknown
    "f1 f0 62 66 f5 f3 44 44",              // buttons
    "37",                                   // mode cycle
    "02 35 00 01 01 ff 01",                 // sound modes: Normal
    "32 01 01 01 01 02 01 00 00 00 00 00 00 00 00 00 00 00 00 00"
)

@Suite struct Q20iTests {
    let model = SoundcoreQ20i()

    @Test func readsSoundModesFromRealState() {
        #expect(q20iStateBody.count == 61)
        let modes = model.soundModes(inState: q20iStateBody)
        #expect(modes?.bytes == hex("00 ff ff 01 01 ff"))
        #expect(modes?.ambient == .noiseCanceling)
    }

    @Test func switchingChangesOnlyTheAmbientByte() throws {
        let current = try #require(model.soundModes(inState: q20iStateBody))
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

        var modes = try #require(model.soundModes(inState: q20iStateBody))
        var seen: [AmbientSoundMode] = []
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
    let model = SoundcoreR50iNC()

    @Test func readsSoundModesFromRealState() {
        #expect(r50iNCStateBody.count == 91)
        let modes = model.soundModes(inState: r50iNCStateBody)
        #expect(modes?.bytes == hex("02 35 00 01 01 ff 01"))
        #expect(modes?.ambient == .normal)
    }

    @Test func switchingChangesOnlyTheAmbientByte() throws {
        let current = try #require(model.soundModes(inState: r50iNCStateBody))
        #expect(model.setSoundModesPacket(switchingTo: .noiseCanceling, from: current).encoded()
            == hex("08 ee 00 00 00 06 81 11 00 00 35 00 01 01 ff 01 c5"))
    }

    @Test func appliesRealButtonPushes() throws {
        let pushes = inboundPackets(
            "09 ff 00 00 01 06 01 11 00 00 35 00 01 01 ff 01 58",
            "09 ff 00 00 01 06 01 11 00 01 35 00 01 01 ff 01 59",
            "09 ff 00 00 01 06 01 11 00 02 35 00 01 01 ff 01 5a"
        )
        var modes = try #require(model.soundModes(inState: r50iNCStateBody))
        var seen: [AmbientSoundMode] = []
        for push in pushes {
            modes = try #require(model.applyingChange(push.body, to: modes))
            seen.append(modes.ambient)
            #expect(modes.bytes == push.body)
        }
        #expect(seen == [.noiseCanceling, .transparency, .normal])
    }

    @Test func rejectsPushOfUnexpectedLength() throws {
        let modes = try #require(model.soundModes(inState: r50iNCStateBody))
        #expect(model.applyingChange(hex("01 ff ff ff ff ff"), to: modes) == nil)
    }
}

@Suite struct ModelSelectionTests {
    @Test func matchesRealDeviceNames() {
        #expect(HeadphoneModels.model(forDeviceName: "soundcore Q20i")?.modelNumber == "A3004")
        #expect(HeadphoneModels.model(forDeviceName: "🐰soundcore R50i🦋")?.modelNumber == "A3959")
        #expect(HeadphoneModels.model(forDeviceName: "AirPods Pro") == nil)
    }

    @Test func rejectsStateOfAnotherLayout() {
        #expect(SoundcoreQ20i().soundModes(inState: r50iNCStateBody) == nil)
        #expect(SoundcoreR50iNC().soundModes(inState: q20iStateBody) == nil)
        #expect(SoundcoreR50iNC().soundModes(inState: Array(r50iNCStateBody.dropLast())) == nil)
    }

    @Test func soundModesRequireValidAmbientByte() {
        #expect(SoundModes([]) == nil)
        #expect(SoundModes([0x03, 0x00]) == nil)
        #expect(SoundModes([0x01])?.ambient == .transparency)
    }
}
