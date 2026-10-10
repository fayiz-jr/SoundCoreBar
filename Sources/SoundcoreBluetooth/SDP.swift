import Foundation
@preconcurrency import IOBluetooth
import SoundcoreKit

extension IOBluetoothDevice {
    /// RFCOMM services from the device's SDP records. These are cached by macOS;
    /// call `performSDPQuery` first for fresh ones.
    public var rfcommServices: [RFCOMMService] {
        let records = (services as? [IOBluetoothSDPServiceRecord]) ?? []
        return records.compactMap(RFCOMMService.init(record:))
    }
}

extension RFCOMMService {
    init?(record: IOBluetoothSDPServiceRecord) {
        var channelID: BluetoothRFCOMMChannelID = 0
        guard record.getRFCOMMChannelID(&channelID) == kIOReturnSuccess else { return nil }
        let classList = record.getAttributeDataElement(
            BluetoothSDPServiceAttributeID(kBluetoothSDPAttributeIdentifierServiceClassIDList.rawValue)
        )
        self.init(name: record.getServiceName(), channelID: channelID, serviceClassUUIDs: Self.uuids(in: classList))
    }

    /// The spec says the service class list is a sequence of UUIDs, but some Soundcore firmware
    /// (JieLi chips, e.g. the R50i NC) stores a single bare UUID there, so accept both.
    private static func uuids(in element: IOBluetoothSDPDataElement?) -> [UUID] {
        guard let element else { return [] }
        switch Int(element.getTypeDescriptor()) {
        case kBluetoothSDPDataElementTypeUUID:
            return element.getUUIDValue()?.foundationUUID.map { [$0] } ?? []
        case kBluetoothSDPDataElementTypeDataElementSequence,
             kBluetoothSDPDataElementTypeDataElementAlternative:
            let children = (element.getArrayValue() as? [IOBluetoothSDPDataElement]) ?? []
            return children.flatMap { uuids(in: $0) }
        default:
            return []
        }
    }
}

extension IOBluetoothSDPUUID {
    /// The full 128-bit UUID (16- and 32-bit short forms are expanded with the Bluetooth base UUID).
    var foundationUUID: UUID? {
        guard let full = getWithLength(16) else { return nil }
        let b = [UInt8](Data(referencing: full))
        guard b.count == 16 else { return nil }
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                           b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }
}
