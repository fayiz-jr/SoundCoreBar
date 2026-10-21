// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 fayiz-jr

import Foundation

public enum FormFactor: String, Codable, Sendable {
    case overEar
    case earbuds
}

/// Where one Soundcore model keeps its noise control in its state (01 01) reply. A model is plain
/// data: the built-in ones (`HeadphoneModels.builtIn`) come from OpenSCQ30's research.
public struct HeadphoneModel: Codable, Hashable, Sendable, Identifiable {
    /// Model numbers that share this layout, e.g. ["A3959"]. Their serial numbers start with the
    /// model number's digits ("3959…"). Headphones set up by hand have just those digits.
    public var modelNumbers: [String]
    public var name: String
    /// How the model appears in Bluetooth names, e.g. "Life Note 3". Models without a serial number
    /// in their state reply are recognised by these, as whole words.
    public var nameKeywords: [String]
    public var formFactor: FormFactor
    /// Where the 16-character serial number starts in the state reply, if it has one.
    public var serialOffset: Int?
    /// Where the sound-modes block starts in the state reply, and how long it is. The set (06 81)
    /// packet echoes the whole block back with only byte 0, the mode, changed.
    public var soundModesOffset: Int
    public var soundModesLength: Int
    /// Whether "sound modes changed" (06 01) pushes carry the whole block. Otherwise only byte 0
    /// of a push is read: the Q20i's is [mode, ff ff ff ff ff].
    public var pushCarriesBlock: Bool
    /// Modes besides 0–2 that byte 0 can hold, such as the Liberty 4 Pro's airplane mode (3). The
    /// app shows no mode while one of these is on and never switches to one.
    public var extraModes: [UInt8]
    /// Tested on real headphones of this model. The others are shown as Beta.
    public var verified: Bool
    /// For replies in the tagged format (`TaggedState`): the entries whose values, one after the
    /// other, make up the sound-modes block, and the entry holding the serial number. The offsets
    /// above are then unused.
    public var soundModesTags: [UInt8]?
    public var serialTag: UInt8?
    /// False for models whose state reply doesn't follow mode changes while connected (the
    /// Liberty 5 Pro): their mode is followed through change notices alone, never re-read.
    public var stateUpdatesLive: Bool?

    public init(modelNumbers: [String], name: String, nameKeywords: [String], formFactor: FormFactor,
                serialOffset: Int?, soundModesOffset: Int, soundModesLength: Int, pushCarriesBlock: Bool,
                extraModes: [UInt8] = [], verified: Bool = false, soundModesTags: [UInt8]? = nil,
                serialTag: UInt8? = nil, stateUpdatesLive: Bool? = nil) {
        self.modelNumbers = modelNumbers
        self.name = name
        self.nameKeywords = nameKeywords
        self.formFactor = formFactor
        self.serialOffset = serialOffset
        self.soundModesOffset = soundModesOffset
        self.soundModesLength = soundModesLength
        self.pushCarriesBlock = pushCarriesBlock
        self.extraModes = extraModes
        self.verified = verified
        self.soundModesTags = soundModesTags
        self.serialTag = serialTag
        self.stateUpdatesLive = stateUpdatesLive
    }

    /// Whether reading the state again confirms a switch.
    public var stateFollowsChanges: Bool { stateUpdatesLive ?? true }

    public var id: String { modelNumbers.isEmpty ? name : modelNumbers.joined(separator: "/") }

    public var soundModesRange: Range<Int> { soundModesOffset..<(soundModesOffset + soundModesLength) }

    /// Whether a state reply's serial number is one of this model's, or nil if the model's replies
    /// carry none.
    public func serialMatches(_ state: [UInt8]) -> Bool? {
        if let serialTag {
            guard let serial = TaggedState.value(serialTag, in: state), serial.count >= 4 else { return false }
            return modelNumbers.contains { $0.drop(while: \.isLetter).prefix(4) == String(decoding: serial.prefix(4), as: UTF8.self) }
        }
        guard let serialOffset else { return nil }
        guard state.count >= serialOffset + 4 else { return false }
        let prefix = String(decoding: state[serialOffset..<(serialOffset + 4)], as: UTF8.self)
        return modelNumbers.contains { $0.drop(while: \.isLetter).prefix(4) == prefix }
    }

    /// Whether a Bluetooth name contains one of the keywords as whole words, so "Life Note 3" is
    /// not found in "Life Note 3S".
    public func matches(deviceName: String) -> Bool {
        nameKeywords.contains { Self.name(deviceName, containsWord: $0) }
    }

    /// The sound-modes block in a state reply, or nil if the reply is not in this model's layout.
    /// Firmware updates can add bytes at the end, so longer replies are accepted.
    public func soundModes(inState state: [UInt8]) -> SoundModes? {
        if let soundModesTags {
            guard serialMatches(state) != false else { return nil }
            let values = soundModesTags.map { TaggedState.value($0, in: state) }
            guard values.allSatisfy({ $0 != nil }) else { return nil }
            let block = values.flatMap { $0! }
            guard block.count == soundModesLength else { return nil }
            return SoundModes(block, extraModes: Set(extraModes))
        }
        guard state.count >= soundModesRange.upperBound, serialMatches(state) != false,
              let modes = SoundModes(Array(state[soundModesRange]), extraModes: Set(extraModes))
        else { return nil }
        // Without a serial number to confirm the layout, OpenSCQ30's 4-byte block has to look right.
        if serialOffset == nil, modes.bytes.count == 4, !Self.isPlausibleFourByteBlock(modes.bytes) { return nil }
        return modes
    }

    /// Applies a "sound modes changed" (06 01) push to the last known block. Nil for a push that
    /// does not fit, after which the state is read again.
    public func applyingChange(_ push: [UInt8], to current: SoundModes) -> SoundModes? {
        let extraModes = Set(extraModes)
        if pushCarriesBlock {
            guard push.count == current.bytes.count else { return nil }
            return SoundModes(push, extraModes: extraModes)
        }
        guard let mode = push.first, AmbientSoundMode(rawValue: mode) != nil || extraModes.contains(mode) else {
            return nil
        }
        return current.withMode(byte: mode)
    }

    /// The set-sound-modes packet that switches to `mode`: the last block the headphones sent,
    /// with only the mode changed.
    public func setSoundModesPacket(switchingTo mode: AmbientSoundMode, from current: SoundModes) -> Packet {
        Packet(.outbound, .setSoundModes, body: current.withAmbient(mode).bytes)
    }

    /// OpenSCQ30's 4-byte block: [mode, noise cancelling mode 0–3, transparency mode 0–1,
    /// custom noise cancelling 0–10], where ff means "not used".
    static func isPlausibleFourByteBlock(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 4 else { return false }
        return (bytes[1] <= 3 || bytes[1] == 0xFF)
            && (bytes[2] <= 1 || bytes[2] == 0xFF)
            && (bytes[3] <= 10 || bytes[3] == 0xFF)
    }

    static func name(_ name: String, containsWord word: String) -> Bool {
        func isWordCharacter(_ character: Character?) -> Bool {
            character.map { $0.isLetter || $0.isNumber } ?? false
        }
        var searchRange = name.startIndex..<name.endIndex
        while let found = name.range(of: word, options: .caseInsensitive, range: searchRange) {
            let before = found.lowerBound > name.startIndex ? name[name.index(before: found.lowerBound)] : nil
            let after = found.upperBound < name.endIndex ? name[found.upperBound] : nil
            if !isWordCharacter(before), !isWordCharacter(after) { return true }
            searchRange = name.index(after: found.lowerBound)..<name.endIndex
        }
        return false
    }
}

public enum HeadphoneModels {
    /// Which model sent a state reply. A serial number that starts with a model's number settles
    /// it whatever the headphones are called. A model whose replies have no serial number is only
    /// considered when the Bluetooth name names it, and its block must pass a stricter check.
    public static func identify(state: [UInt8], deviceName: String,
                                among models: [HeadphoneModel] = builtIn) -> HeadphoneModel? {
        models.first { $0.serialMatches(state) == true && $0.soundModes(inState: state) != nil }
            ?? models.first {
                $0.serialOffset == nil && $0.serialTag == nil && $0.matches(deviceName: deviceName)
                    && $0.soundModes(inState: state) != nil
            }
    }

    /// Whether a Bluetooth device's name suggests Soundcore headphones worth asking for their state.
    /// (Renamed ones are also found by their vendor service; see `SoundcoreServiceUUID`.)
    public static func isCandidate(deviceName: String, among models: [HeadphoneModel] = builtIn) -> Bool {
        deviceName.range(of: "soundcore", options: .caseInsensitive) != nil
            || models.contains { $0.matches(deviceName: deviceName) }
    }
}
