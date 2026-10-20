// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 fayiz-jr

import Testing
@testable import SoundcoreKit

/// The state with the block at `range` replaced.
private func state(_ state: [UInt8], with block: [UInt8], at offset: Int) -> [UInt8] {
    var state = state
    state.replaceSubrange(offset..<(offset + block.count), with: block)
    return state
}

@Suite struct LearnerTests {
    @Test func learnsTheQ20iFromItsButtonPresses() throws {
        var learner = ModelLearner()
        learner.record(state: q20iState, as: .noiseCanceling)
        for (mode, push) in [(AmbientSoundMode.transparency, "01 ff ff ff ff ff"), (.normal, "02 ff ff ff ff ff")] {
            learner.record(notice: hex(push))
            learner.record(state: state(q20iState, with: [mode.rawValue], at: 35), as: mode)
        }
        let finding = try learner.analyse().get()
        #expect(finding == .init(soundModesOffset: 35, soundModesLength: 6, pushCarriesBlock: false, serialOffset: 7))

        let model = learner.model(finding, deviceName: "soundcore Q20i", formFactor: .overEar)
        #expect(model.modelNumbers == ["3004"])
        #expect(HeadphoneModels.identify(state: q20iState, deviceName: "renamed", among: [model]) == model)
        #expect(model.setSoundModesPacket(switchingTo: .transparency, from: model.soundModes(inState: q20iState)!)
            == builtIn("A3004").setSoundModesPacket(switchingTo: .transparency, from: builtIn("A3004").soundModes(inState: q20iState)!))
    }

    @Test func learnsTheR50iNCFromItsButtonPresses() throws {
        var learner = ModelLearner()
        learner.record(state: r50iNCState(), as: .normal)
        for (mode, push) in [(AmbientSoundMode.noiseCanceling, "00 35 00 01 01 ff 01"), (.transparency, "01 35 00 01 01 ff 01")] {
            learner.record(notice: hex(push))
            learner.record(state: state(r50iNCState(), with: hex(push), at: 64), as: mode)
        }
        let finding = try learner.analyse().get()
        #expect(finding == .init(soundModesOffset: 64, soundModesLength: 7, pushCarriesBlock: true, serialOffset: 16))
    }

    /// Given each model's state in all three modes and one button notice, the learner finds the
    /// same layout as the built-in table.
    @Test(arguments: openSCQ30Fixtures.map(\.model))
    func rediscoversBuiltInLayout(_ modelNumber: String) throws {
        let fixture = try #require(openSCQ30Fixtures.first { $0.model == modelNumber })
        let model = builtIn(modelNumber)
        let block = try #require(model.soundModes(inState: fixture.state))
        var learner = ModelLearner()
        for mode in AmbientSoundMode.allCases {
            let modes = block.withAmbient(mode)
            learner.record(state: state(fixture.state, with: modes.bytes, at: model.soundModesOffset), as: mode)
        }
        learner.record(notice: block.withAmbient(.transparency).bytes)
        let finding = try learner.analyse().get()
        #expect(finding.soundModesOffset == model.soundModesOffset)
        #expect(finding.soundModesLength == model.soundModesLength)
        #expect(finding.serialOffset == model.serialOffset)
    }

    @Test func needsTwoModesAndANotice() {
        var learner = ModelLearner()
        learner.record(state: q20iState, as: .noiseCanceling)
        #expect(learner.analyse() == .failure(.tooFewModes))
        learner.record(state: state(q20iState, with: [1], at: 35), as: .transparency)
        #expect(learner.analyse() == .failure(.noChangeNotice))
        learner.record(notice: hex("01 ff ff ff ff ff"))
        #expect(learner.analyse().map(\.soundModesOffset) == .success(35))
    }

    @Test func refusesToGuessBetweenTwoMatchingBytes() {
        // A second byte that always equals the mode, and notices that do not settle it.
        var learner = ModelLearner()
        for mode in [AmbientSoundMode.noiseCanceling, .transparency] {
            var state = state(q20iState, with: [mode.rawValue], at: 35)
            state[50] = mode.rawValue
            learner.record(state: state, as: mode)
        }
        learner.record(notice: hex("01 ff ff ff ff ff"))
        #expect(learner.analyse() == .failure(.ambiguous(offsets: [35, 50])))
    }

    @Test func noticesThatRepeatTheBlockSettleIt() throws {
        var learner = ModelLearner()
        for mode in [AmbientSoundMode.noiseCanceling, .transparency] {
            var state = state(r50iNCState(), with: [mode.rawValue], at: 64)
            state[80] = mode.rawValue
            learner.record(state: state, as: mode)
        }
        learner.record(notice: hex("01 35 00 01 01 ff 01"))
        #expect(try learner.analyse().get().soundModesOffset == 64)
    }

    @Test func findsSerialNumbersAfterTheFirmwareVersion() {
        #expect(ModelLearner.serialOffset(in: q20iState) == 7)
        #expect(ModelLearner.serialOffset(in: r50iNCState()) == 16)
        #expect(ModelLearner.serialOffset(in: [0, 1, 2, 3]) == nil)
    }

    @Test func reportsHoldNoSerialNumber() throws {
        let realLooking = state(q20iState, with: Array("3004AB12CD34EF56".utf8), at: 7)
        let anonymised = ModelLearner.anonymised(realLooking)
        #expect(Array(anonymised[7..<23]) == Array("3004000000000000".utf8))
        #expect(Array(anonymised[2..<7]) == Array("00.26".utf8))  // the firmware stays

        var learner = ModelLearner()
        learner.record(state: realLooking, as: .noiseCanceling)
        learner.record(notice: hex("01 ff ff ff ff ff"))
        learner.record(state: state(realLooking, with: [1], at: 35), as: .transparency)
        let report = learner.report(deviceName: "soundcore Q20i", finding: learner.analyse(), testPassed: true,
                                    appVersion: "1.1")
        #expect(!report.contains(Array("AB12CD34EF56".utf8).hexString))
        #expect(report.contains("byte 35, 6 bytes"))
        #expect(report.contains("starting 3004"))
    }
}

/// Replies in the tagged format of newer models such as the Liberty 5 Pro, with made-up values.
@Suite struct TaggedFormatTests {
    static let address: [UInt8] = [0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC]

    /// [tag, length, value…] entries: firmware, a serial number, a Bluetooth address and filler.
    static let reply: [UInt8] = {
        var entries: [[UInt8]] = [
            [0x01, 0x01, 0x00], [0x02, 0x01, 0x01], [0x03, 0x02, 0x00, 0x60],
            [0x05, 0x05] + Array("05.52".utf8),
            [0x07, 0x11] + Array("1203AB12CD34EF56".utf8) + [0x00],
            [0x29, 0x06] + address,
        ]
        for tag in UInt8(0x10)..<0x18 { entries.append([tag, 0x02, 0x0F, 0x0F]) }
        return entries.flatMap { $0 }
    }()

    @Test func recognisesTaggedReplies() {
        #expect(ModelLearner.taggedValues(in: Self.reply)?.count == 14)
    }

    @Test func olderRepliesAreNotTagged() {
        #expect(ModelLearner.taggedValues(in: q20iState) == nil)
        #expect(ModelLearner.taggedValues(in: r50iNCState()) == nil)
        for fixture in openSCQ30Fixtures {
            #expect(ModelLearner.taggedValues(in: fixture.state) == nil, "\(fixture.model)")
        }
    }

    @Test func masksAddressesAndSerialNumbers() {
        let masked = ModelLearner.anonymised(Self.reply)
        #expect(!masked.hexString.contains(Self.address.hexString))
        #expect(masked.hexString.contains(Array("1203000000000000".utf8).hexString))
        #expect(masked.hexString.contains(Array("05.52".utf8).hexString))  // the firmware stays
        #expect(masked.count == Self.reply.count)
    }

    @Test func reportsIdenticalRepliesAndOtherMessages() {
        var learner = ModelLearner()
        for mode in AmbientSoundMode.allCases { learner.record(state: Self.reply, as: mode) }
        learner.record(otherMessage: Command(0x0A, 0x01), body: Self.reply)
        let report = learner.report(deviceName: "soundcore Liberty 5 Pro", finding: learner.analyse(),
                                    testPassed: nil, appVersion: "1.2.1")
        #expect(report.contains("identical in every mode"))
        #expect(report.contains("tagged format"))
        #expect(report.contains("Other messages"))
        #expect(!report.contains(Self.address.hexString))
    }

    @Test func keepsAtMostTheLimitOfOtherMessages() {
        var learner = ModelLearner()
        for _ in 0..<100 { learner.record(otherMessage: Command(0x0A, 0x01), body: [1]) }
        #expect(learner.otherMessages.count == ModelLearner.otherMessageLimit)
    }
}
