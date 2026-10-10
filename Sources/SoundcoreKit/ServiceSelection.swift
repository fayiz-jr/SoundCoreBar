import Foundation

/// An RFCOMM service found by SDP on a device.
public struct RFCOMMService: Equatable, Sendable {
    public var name: String?
    public var channelID: UInt8
    public var serviceClassUUIDs: [UUID]

    public init(name: String?, channelID: UInt8, serviceClassUUIDs: [UUID]) {
        self.name = name
        self.channelID = channelID
        self.serviceClassUUIDs = serviceClassUUIDs
    }
}

public enum SoundcoreServiceUUID {
    /// Standard Serial Port Profile, used when the vendor service is missing.
    public static let serialPort = UUID(uuidString: "00001101-0000-1000-8000-00805F9B34FB")!

    /// Soundcore's vendor service is `0cf12d31-fac3-4553-bd80-d6832e7xxxxx`; the last 5 hex
    /// digits vary by model.
    public static func isVendor(_ uuid: UUID) -> Bool {
        uuid.uuidString.lowercased().hasPrefix("0cf12d31-fac3-4553-bd80-d6832e7")
    }

    /// Picks the vendor service if there is one, otherwise Serial Port.
    public static func preferredService(in services: [RFCOMMService]) -> RFCOMMService? {
        services.first { $0.serviceClassUUIDs.contains(where: isVendor) }
            ?? services.first { $0.serviceClassUUIDs.contains(serialPort) }
    }
}
