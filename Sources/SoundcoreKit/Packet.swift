// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 fayiz-jr

/// Which way a packet travels. Each direction has a fixed 5-byte prefix.
public enum Direction: Sendable {
    /// Mac to headphones.
    case outbound
    /// Headphones to Mac.
    case inbound

    public var prefix: [UInt8] {
        switch self {
        case .outbound: [0x08, 0xEE, 0x00, 0x00, 0x00]
        case .inbound: [0x09, 0xFF, 0x00, 0x00, 0x01]
        }
    }
}

/// The two command bytes that follow the direction prefix.
public struct Command: Hashable, Sendable, CustomStringConvertible {
    public let high: UInt8
    public let low: UInt8

    public init(_ high: UInt8, _ low: UInt8) {
        self.high = high
        self.low = low
    }

    /// Outbound: ask for the full state. Inbound: the full state, in a model-specific layout.
    public static let state = Command(0x01, 0x01)
    /// Outbound: set sound modes. Inbound: the headphones' acknowledgement of that.
    public static let setSoundModes = Command(0x06, 0x81)
    /// Inbound only: the sound modes changed on the headphones (e.g. a button press).
    public static let soundModesChanged = Command(0x06, 0x01)

    public var description: String { [high, low].hexString }
}

/// One framed packet:
/// `[direction, 5 bytes][command, 2 bytes][length, u16 LE][body][checksum, 1 byte]`,
/// where `length` counts the whole packet and `checksum` is the sum of every byte before it, mod 256.
public struct Packet: Equatable, Sendable, CustomStringConvertible {
    public static let headerLength = 9
    public static let checksumLength = 1
    public static let minimumLength = headerLength + checksumLength

    public var direction: Direction
    public var command: Command
    public var body: [UInt8]

    public init(_ direction: Direction, _ command: Command, body: [UInt8] = []) {
        self.direction = direction
        self.command = command
        self.body = body
    }

    public static let requestState = Packet(.outbound, .state)

    public func encoded() -> [UInt8] {
        let length = Self.headerLength + body.count + Self.checksumLength
        precondition(length <= Int(UInt16.max), "packet body too large")
        var bytes = direction.prefix
        bytes.reserveCapacity(length)
        bytes += [command.high, command.low, UInt8(length & 0xFF), UInt8(length >> 8)]
        bytes += body
        bytes.append(Self.checksum(bytes))
        return bytes
    }

    public static func checksum(_ bytes: some Sequence<UInt8>) -> UInt8 {
        bytes.reduce(0, &+)
    }

    public var description: String {
        "\(direction == .inbound ? "in" : "out") \(command) body(\(body.count))=[\(body.hexString)]"
    }
}

/// Reassembles packets from an RFCOMM byte stream, where one read may hold part of a packet or
/// several packets. Bytes that cannot start a valid packet are skipped until the next prefix.
public struct PacketStreamParser: Sendable {
    public let direction: Direction
    private var buffer: [UInt8] = []

    public init(direction: Direction = .inbound) {
        self.direction = direction
    }

    /// Bytes received but not yet part of a complete packet.
    public var pendingByteCount: Int { buffer.count }

    public mutating func reset() {
        buffer.removeAll()
    }

    /// Appends newly received bytes and returns every packet completed by them, in order.
    public mutating func append(_ bytes: some Sequence<UInt8>) -> [Packet] {
        buffer.append(contentsOf: bytes)
        var packets: [Packet] = []
        let prefix = direction.prefix

        while true {
            guard let start = Self.firstIndex(of: prefix, in: buffer) else {
                // Keep only a trailing fragment that could still grow into a prefix.
                buffer.removeFirst(buffer.count - Self.partialPrefixLength(prefix, atEndOf: buffer))
                break
            }
            buffer.removeFirst(start)

            guard buffer.count >= Packet.headerLength else { break }
            let length = Int(buffer[7]) | Int(buffer[8]) << 8
            guard length >= Packet.minimumLength else {
                buffer.removeFirst()
                continue
            }
            guard buffer.count >= length else { break }

            let checksum = Packet.checksum(buffer[0..<(length - 1)])
            guard checksum == buffer[length - 1] else {
                buffer.removeFirst()
                continue
            }
            packets.append(Packet(
                direction,
                Command(buffer[5], buffer[6]),
                body: Array(buffer[Packet.headerLength..<(length - 1)])
            ))
            buffer.removeFirst(length)
        }
        return packets
    }

    private static func firstIndex(of needle: [UInt8], in haystack: [UInt8]) -> Int? {
        guard haystack.count >= needle.count else { return nil }
        return (0...(haystack.count - needle.count)).first { start in
            haystack[start..<(start + needle.count)].elementsEqual(needle)
        }
    }

    private static func partialPrefixLength(_ prefix: [UInt8], atEndOf bytes: [UInt8]) -> Int {
        for length in stride(from: min(prefix.count - 1, bytes.count), to: 0, by: -1)
        where bytes.suffix(length).elementsEqual(prefix.prefix(length)) {
            return length
        }
        return 0
    }
}
