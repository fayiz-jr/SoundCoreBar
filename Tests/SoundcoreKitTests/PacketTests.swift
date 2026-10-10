// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 fayiz-jr

import Testing
@testable import SoundcoreKit

@Suite struct PacketTests {
    @Test func requestStateMatchesKnownBytes() {
        #expect(Packet.requestState.encoded() == bytes(fromHex: "08 ee 00 00 00 01 01 0a 00 02"))
    }

    /// OpenSCQ30's known-good set-sound-modes packets (4-byte body). The Q20i itself turned out to
    /// need a 6-byte body; see SoundcoreQ20i.
    @Test func setSoundModesMatchesOpenSCQ30KnownGoodPackets() {
        let normal = SoundModes(hex("00 00 01 00"))!.withAmbient(.normal)
        #expect(Packet(.outbound, .setSoundModes, body: normal.bytes).encoded()
            == bytes(fromHex: "08 ee 00 00 00 06 81 0e 00 02 00 01 00 8e"))

        let noiseCanceling = SoundModes(hex("02 01 01 00"))!.withAmbient(.noiseCanceling)
        #expect(Packet(.outbound, .setSoundModes, body: noiseCanceling.bytes).encoded()
            == bytes(fromHex: "08 ee 00 00 00 06 81 0e 00 00 01 01 00 8d"))
    }

    @Test func checksumIsSumModulo256() {
        #expect(Packet.checksum([0xFF, 0x02]) == 0x01)
        #expect(Packet.checksum([]) == 0)
    }

    @Test func parsesSinglePacket() {
        var parser = PacketStreamParser()
        let packets = parser.append(bytes(fromHex: "09 ff 00 00 01 06 81 0a 00 9a")!)
        #expect(packets == [Packet(.inbound, .setSoundModes)])
        #expect(parser.pendingByteCount == 0)
    }

    @Test func reassemblesPacketSplitAcrossReads() {
        let full = Packet(.inbound, .soundModesChanged, body: [0x02, 0x01, 0x00, 0x00]).encoded()
        var parser = PacketStreamParser()
        for split in [3, 6, 11] {
            parser.reset()
            #expect(parser.append(full[..<split]).isEmpty)
            #expect(parser.append(full[split...]) == [Packet(.inbound, .soundModesChanged, body: [0x02, 0x01, 0x00, 0x00])])
        }
    }

    @Test func parsesSeveralPacketsInOneRead() {
        let first = Packet(.inbound, .setSoundModes)
        let second = Packet(.inbound, .soundModesChanged, body: [0x00, 0x01, 0x01, 0x00])
        var parser = PacketStreamParser()
        #expect(parser.append(first.encoded() + second.encoded()) == [first, second])
    }

    @Test func skipsGarbageAndBadChecksums() {
        let good = Packet(.inbound, .setSoundModes)
        var corrupt = Packet(.inbound, .soundModesChanged, body: [1, 2, 3]).encoded()
        corrupt[corrupt.count - 1] &+= 1
        var parser = PacketStreamParser()
        #expect(parser.append([0x00, 0x13, 0x09] + corrupt + good.encoded()) == [good])
        #expect(parser.pendingByteCount == 0)
    }

    @Test func keepsPartialPrefixAtEndOfRead() {
        let packet = Packet(.inbound, .setSoundModes)
        let bytes = packet.encoded()
        var parser = PacketStreamParser()
        #expect(parser.append([0x55] + bytes[..<2]).isEmpty)
        #expect(parser.pendingByteCount == 2)
        #expect(parser.append(bytes[2...]) == [packet])
    }

    @Test func hexRoundTrips() {
        #expect(bytes(fromHex: "0a ff 00")! == [0x0A, 0xFF, 0x00])
        #expect([UInt8]([0x0A, 0xFF, 0x00]).hexString == "0a ff 00")
        #expect(bytes(fromHex: "0") == nil)
        #expect(bytes(fromHex: "zz") == nil)
    }
}
