import CoreBluetooth

/// Gets Bluetooth access before any IOBluetooth call. CoreBluetooth shows the system prompt and
/// reports the answer, which IOBluetooth alone does not.
public final class BluetoothPermission: NSObject {
    private var central: CBCentralManager?
    private var completion: ((Bool) -> Void)?

    public override init() {}

    /// Calls `completion` with whether access is granted, asking the user first if they never answered.
    public func request(_ completion: @escaping (Bool) -> Void) {
        switch CBManager.authorization {
        case .allowedAlways:
            completion(true)
        case .notDetermined:
            self.completion = completion
            central = CBCentralManager(delegate: self, queue: nil)
        default:
            completion(false)
        }
    }
}

extension BluetoothPermission: @preconcurrency CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard CBManager.authorization != .notDetermined, let completion else { return }
        self.completion = nil
        self.central = nil
        completion(CBManager.authorization == .allowedAlways)
    }
}
