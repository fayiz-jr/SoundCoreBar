// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 fayiz-jr

extension Sequence<UInt8> {
    /// Lowercase hex bytes separated by spaces, e.g. `08 ee 00`.
    public var hexString: String {
        map { byte in
            let digits = String(byte, radix: 16)
            return byte < 0x10 ? "0" + digits : digits
        }
        .joined(separator: " ")
    }
}

/// Parses `"08 ee 00"` (spaces optional) into bytes. Returns nil on malformed input.
public func bytes(fromHex hex: String) -> [UInt8]? {
    let digits = hex.filter { !$0.isWhitespace }
    guard digits.count.isMultiple(of: 2) else { return nil }
    var result: [UInt8] = []
    var index = digits.startIndex
    while index < digits.endIndex {
        let next = digits.index(index, offsetBy: 2)
        guard let byte = UInt8(digits[index..<next], radix: 16) else { return nil }
        result.append(byte)
        index = next
    }
    return result
}
