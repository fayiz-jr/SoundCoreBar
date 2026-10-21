// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 fayiz-jr

/// The settings reply of newer models such as the Liberty 5 Pro: [tag, length, value…] entries to
/// the very end, instead of fields at fixed places. Entries can change length between firmware
/// versions, so values are found by tag.
public enum TaggedState {
    /// Each entry's tag and where its value is, or nil if the reply isn't in this format.
    public static func entries(in bytes: [UInt8]) -> [(tag: UInt8, value: Range<Int>)]? {
        var entries: [(tag: UInt8, value: Range<Int>)] = []
        var index = 0
        while index + 2 <= bytes.count {
            let end = index + 2 + Int(bytes[index + 1])
            guard end <= bytes.count else { return nil }
            entries.append((bytes[index], (index + 2)..<end))
            index = end
        }
        // Ending exactly on an entry many times over doesn't happen by chance.
        return index == bytes.count && entries.count >= 10 ? entries : nil
    }

    /// The value of the first entry with this tag.
    public static func value(_ tag: UInt8, in bytes: [UInt8]) -> [UInt8]? {
        entries(in: bytes)?.first { $0.tag == tag }.map { Array(bytes[$0.value]) }
    }
}
