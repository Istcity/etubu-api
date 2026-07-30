import Foundation
import CoreBluetooth

/// Persists the last successful OBD peripheral for auto-reconnect.
enum EtubuObdDeviceStore {
    private static let uuidKey = "etubu.obd.lastPeripheralUUID"
    private static let nameKey = "etubu.obd.lastPeripheralName"

    static var lastUUID: UUID? {
        get {
            guard let s = UserDefaults.standard.string(forKey: uuidKey) else { return nil }
            return UUID(uuidString: s)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.uuidString, forKey: uuidKey)
            } else {
                UserDefaults.standard.removeObject(forKey: uuidKey)
            }
        }
    }

    static var lastName: String? {
        get { UserDefaults.standard.string(forKey: nameKey) }
        set {
            if let newValue, !newValue.isEmpty {
                UserDefaults.standard.set(newValue, forKey: nameKey)
            } else {
                UserDefaults.standard.removeObject(forKey: nameKey)
            }
        }
    }

    static func remember(_ peripheral: CBPeripheral) {
        lastUUID = peripheral.identifier
        lastName = peripheral.name ?? lastName ?? "OBD"
    }

    static func clear() {
        lastUUID = nil
        lastName = nil
    }
}
