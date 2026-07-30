import Foundation
import CoreBluetooth

/// Ensures CoreBluetooth is powered on (and the system permission prompt has run)
/// before Tesla BLE connect attempts.
@MainActor
final class EtubuBluetoothGate: NSObject, CBCentralManagerDelegate {
    static let shared = EtubuBluetoothGate()

    private var central: CBCentralManager?
    private var waiters: [CheckedContinuation<Bool, Never>] = []

    private override init() {
        super.init()
    }

    /// Returns true when Bluetooth is powered on (after prompting if needed).
    func waitUntilReady(timeoutSeconds: Double = 8) async -> Bool {
        if central?.state == .poweredOn { return true }
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main, options: [
                CBCentralManagerOptionShowPowerAlertKey: true
            ])
        }
        // State may already be available synchronously after init.
        if central?.state == .poweredOn { return true }
        if let state = central?.state, [.unauthorized, .unsupported, .poweredOff].contains(state) {
            return false
        }

        return await withCheckedContinuation { cont in
            waiters.append(cont)
            let timeout = timeoutSeconds
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let self else { return }
                guard !self.waiters.isEmpty else { return }
                let pending = self.waiters
                self.waiters.removeAll()
                let ok = self.central?.state == .poweredOn
                pending.forEach { $0.resume(returning: ok) }
            }
        }
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            let ok = central.state == .poweredOn
            let terminal = ok || [.unauthorized, .unsupported, .poweredOff].contains(central.state)
            if terminal, !waiters.isEmpty {
                let pending = waiters
                waiters.removeAll()
                pending.forEach { $0.resume(returning: ok) }
            }
            if central.state == .poweredOff {
                EtubuVehicleTelemetry.shared.statusMessage = "Bluetooth kapalı"
            } else if central.state == .unauthorized {
                EtubuVehicleTelemetry.shared.statusMessage = "Bluetooth izni gerekli"
            }
        }
    }
}
