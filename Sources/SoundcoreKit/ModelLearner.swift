// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 fayiz-jr

import Foundation

/// Works out where unknown Soundcore headphones keep their noise control. The user puts them in
/// each mode with their own button while state replies are read, and the button presses cause
/// "sound modes changed" (06 01) notices:
///
/// - the notice is one whole sound-modes block (OpenSCQ30 reads it that way for every model, and so
///   do the Q20i and R50i NC), so its length is the block's length;
/// - the block starts at the one byte of the state that always holds the mode the headphones are in.
public struct ModelLearner: Sendable {
    public struct Sample: Equatable, Sendable {
        public let mode: AmbientSoundMode
        public let state: [UInt8]
    }

    public enum Problem: Error, Equatable, Sendable {
        /// Fewer than two different modes were recorded.
        case tooFewModes
        /// No change notice arrived, so the block's length is unknown.
        case noChangeNotice
        /// Change notices of different lengths.
        case inconsistentNotices
        /// No byte of the state follows the mode.
        case noModeByte
        /// Several bytes follow the mode, and nothing tells them apart.
        case ambiguous(offsets: [Int])
    }

    public struct Finding: Equatable, Sendable {
        public let soundModesOffset: Int
        public let soundModesLength: Int
        public let pushCarriesBlock: Bool
        public let serialOffset: Int?
    }

    public private(set) var samples: [Sample] = []
    public private(set) var notices: [[UInt8]] = []
    /// Messages of other kinds that arrived meanwhile, such as a newer model's own notices. Kept
    /// for the report only.
    public private(set) var otherMessages: [(command: Command, body: [UInt8])] = []
    /// The most kept, so that a chatty pair of headphones can't make the report huge.
    static let otherMessageLimit = 40

    public init() {}

    public mutating func record(state: [UInt8], as mode: AmbientSoundMode) {
        samples.append(Sample(mode: mode, state: state))
    }

    public mutating func record(notice: [UInt8]) {
        notices.append(notice)
    }

    public mutating func record(otherMessage command: Command, body: [UInt8]) {
        guard otherMessages.count < Self.otherMessageLimit else { return }
        otherMessages.append((command, body))
    }

    public var recordedModes: Set<AmbientSoundMode> { Set(samples.map(\.mode)) }

    public func analyse() -> Result<Finding, Problem> {
        guard recordedModes.count >= 2 else { return .failure(.tooFewModes) }
        let modeNotices = notices.filter { $0.first.flatMap(AmbientSoundMode.init(rawValue:)) != nil }
        guard let length = modeNotices.first?.count else { return .failure(.noChangeNotice) }
        guard modeNotices.allSatisfy({ $0.count == length }) else { return .failure(.inconsistentNotices) }
        let shortest = samples.map(\.state.count).min() ?? 0
        guard shortest >= length else { return .failure(.noModeByte) }

        var offsets = (0...(shortest - length)).filter { offset in
            samples.allSatisfy { $0.state[offset] == $0.mode.rawValue }
        }
        // A byte that only happens to follow the mode is told apart by a notice that repeats the
        // whole block, when the headphones send those. A notice padded with ff (the Q20i's) would
        // match any run of ff, so it settles nothing.
        let telling = modeNotices.filter { $0.dropFirst().contains { $0 != 0xFF } }
        if offsets.count > 1 {
            let repeated = offsets.filter { noticesRepeatBlock(at: $0, length: length, among: telling) }
            if !repeated.isEmpty { offsets = repeated }
        }
        guard offsets.count == 1, let offset = offsets.first else {
            return .failure(offsets.isEmpty ? .noModeByte : .ambiguous(offsets: offsets))
        }
        let serialOffsets = Set(samples.map { Self.serialOffset(in: $0.state) })
        return .success(Finding(
            soundModesOffset: offset,
            soundModesLength: length,
            pushCarriesBlock: noticesRepeatBlock(at: offset, length: length, among: modeNotices),
            serialOffset: serialOffsets.count == 1 ? serialOffsets.first! : nil
        ))
    }

    /// The model for these headphones. With a serial number it is recognised by the serial's first
    /// four characters (the model number's digits on every known model), otherwise by `deviceName`.
    public func model(_ finding: Finding, deviceName: String, formFactor: FormFactor) -> HeadphoneModel {
        let digits = finding.serialOffset.map { offset in
            String(decoding: samples[0].state[offset..<(offset + 4)], as: UTF8.self)
        }
        return HeadphoneModel(
            modelNumbers: digits.map { [$0] } ?? [],
            name: deviceName,
            nameKeywords: [deviceName],
            formFactor: formFactor,
            serialOffset: finding.serialOffset,
            soundModesOffset: finding.soundModesOffset,
            soundModesLength: finding.soundModesLength,
            pushCarriesBlock: finding.pushCarriesBlock,
            verified: true
        )
    }

    private func noticesRepeatBlock(at offset: Int, length: Int, among notices: [[UInt8]]) -> Bool {
        notices.contains { notice in
            samples.contains { $0.mode.rawValue == notice[0] && Array($0.state[offset..<(offset + length)]) == notice }
        }
    }

    // MARK: Serial numbers

    /// Where the 16-character serial number starts, if the state has one that names the model.
    /// On every model OpenSCQ30 knows, it directly follows the firmware version ("01.65", once or
    /// twice) and is digits and letters, its first four the model number's digits. Failing that,
    /// it is the only run of exactly 16 letters and digits. A serial of zeros (some firmware
    /// reports one) names nothing.
    public static func serialOffset(in state: [UInt8]) -> Int? {
        func isSerial(at offset: Int) -> Bool {
            offset >= 0 && offset + 16 <= state.count
                && state[offset..<(offset + 16)].allSatisfy(isAlphanumeric)
                && state[offset..<(offset + 4)].allSatisfy(isDigit)
                && state[offset..<(offset + 4)] != [0x30, 0x30, 0x30, 0x30]
        }
        let afterFirmware = state.indices.dropLast(4).filter { index in
            isDigit(state[index]) && isDigit(state[index + 1]) && state[index + 2] == UInt8(ascii: ".")
                && isDigit(state[index + 3]) && isDigit(state[index + 4])
        }.map { $0 + 5 }
        if let offset = afterFirmware.last(where: isSerial) { return offset }

        let runs = runs(in: state.count) { isAlphanumeric(state[$0]) }.filter { $0.count == 16 }
        return runs.count == 1 && isSerial(at: runs[0].lowerBound) ? runs[0].lowerBound : nil
    }

    /// The state with anything that could identify the headphones masked: the serial number and
    /// any other run of 8 or more letters and digits keep their first four characters, the rest
    /// become "0". In the newer tagged format (see `taggedValues`), every 6-byte value becomes
    /// zeros too, since those hold Bluetooth addresses.
    public static func anonymised(_ state: [UInt8]) -> [UInt8] {
        var state = state
        for value in taggedValues(in: state) ?? [] where value.count == 6 {
            for index in value { state[index] = 0 }
        }
        var serialRange = 0..<0
        if let serial = serialOffset(in: state) {
            serialRange = serial..<(serial + 16)
            for index in (serial + 4)..<(serial + 16) { state[index] = UInt8(ascii: "0") }
        }
        let others = runs(in: state.count) { !serialRange.contains($0) && isAlphanumeric(state[$0]) }
        for run in others where run.count >= 8 {
            for index in (run.lowerBound + 4)..<run.upperBound { state[index] = UInt8(ascii: "0") }
        }
        return state
    }

    /// Where the values are, if the reply is in the tagged format of newer models such as the
    /// Liberty 5 Pro: [tag, length, value…] repeated to the very end. Nil for any other reply.
    static func taggedValues(in bytes: [UInt8]) -> [Range<Int>]? {
        var values: [Range<Int>] = []
        var index = 0
        while index + 2 <= bytes.count {
            let end = index + 2 + Int(bytes[index + 1])
            guard end <= bytes.count else { return nil }
            values.append((index + 2)..<end)
            index = end
        }
        // Ending exactly on an entry many times over doesn't happen by chance.
        return index == bytes.count && values.count >= 10 ? values : nil
    }

    private static func isDigit(_ byte: UInt8) -> Bool { (0x30...0x39).contains(byte) }

    private static func isAlphanumeric(_ byte: UInt8) -> Bool {
        isDigit(byte) || (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)
    }

    /// The runs of consecutive indices in 0..<count that match.
    private static func runs(in count: Int, where matches: (Int) -> Bool) -> [Range<Int>] {
        var runs: [Range<Int>] = []
        var start: Int?
        for index in 0..<count {
            if matches(index) {
                if start == nil { start = index }
            } else if let runStart = start {
                runs.append(runStart..<index)
                start = nil
            }
        }
        if let start { runs.append(start..<count) }
        return runs
    }

    // MARK: Sharing

    /// A report for a GitHub issue, so the model can be added for everyone. Holds no serial number
    /// or Bluetooth address (as far as they can be told apart); the Bluetooth name is the one thing
    /// to check before sharing.
    public func report(deviceName: String, finding: Result<Finding, Problem>, testPassed: Bool?,
                       appVersion: String) -> String {
        var lines = [
            "### Headphones set up in SoundcoreBar",
            "",
            "- Bluetooth name: \(deviceName)",
            "- SoundcoreBar \(appVersion)",
        ]
        switch finding {
        case .success(let finding):
            let recognition = finding.serialOffset.map { offset in
                let digits = String(decoding: samples[0].state[offset..<(offset + 4)], as: UTF8.self)
                return "serial number at byte \(offset), starting \(digits)"
            } ?? "no serial number found; recognised by name"
            lines += [
                "- Sound modes: byte \(finding.soundModesOffset), \(finding.soundModesLength) bytes; "
                    + "change notices \(finding.pushCarriesBlock ? "repeat the whole block" : "carry only the mode")",
                "- Recognition: \(recognition)",
                "- Test switch: \(testPassed.map { $0 ? "worked" : "did not work" } ?? "not run")",
            ]
        case .failure(let problem):
            lines.append("- Could not work out the layout: \(problem)")
        }
        if samples.count > 1, Set(samples.map(\.state)).count == 1 {
            lines.append("- The state replies were identical in every mode")
        }
        if let first = samples.first, Self.taggedValues(in: first.state) != nil {
            lines.append("- The replies are in the newer tagged format; 6-byte values (Bluetooth addresses) are zeroed")
        }
        lines += ["", "State replies (serial number masked):", "```"]
        for sample in samples {
            lines.append("\(sample.mode.title) (\(sample.state.count) bytes): \(Self.anonymised(sample.state).hexString)")
        }
        lines.append("```")
        if !notices.isEmpty {
            lines += ["", "Change notices from the headphones' button:", "```"]
            lines += notices.map(\.hexString)
            lines.append("```")
        }
        if !otherMessages.isEmpty {
            lines += ["", "Other messages from the headphones (command: body):", "```"]
            lines += otherMessages.map { "\($0.command): \(Self.anonymised($0.body).hexString)" }
            lines.append("```")
        }
        return lines.joined(separator: "\n")
    }
}
