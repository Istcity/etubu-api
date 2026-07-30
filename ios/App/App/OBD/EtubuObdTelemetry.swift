import Foundation
import Combine

enum EtubuObdConnectionState: String, Equatable {
    case idle
    case scanning
    case connecting
    case connected
    case reconnecting
    case disconnected
    case bluetoothUnavailable = "bluetooth_unavailable"
    case scanTimeout = "scan_timeout"
    case connectFailed = "connect_failed"
}

struct EtubuObdDiscoveredDevice: Identifiable, Equatable {
    let id: UUID
    let name: String
    let rssi: Int
}

/// Live OBD telemetry for SwiftUI dashboard + Capacitor bridge.
final class EtubuObdTelemetry: ObservableObject {
    static let shared = EtubuObdTelemetry()

    @Published var connectionState: EtubuObdConnectionState = .idle
    @Published var deviceName: String = "OBD"
    @Published var kmh: Int = 0
    @Published var rpm: Int = 0
    @Published var coolantC: Int?
    @Published var voltageV: Double?
    @Published var throttlePct: Int?
    @Published var engineLoadPct: Int?
    @Published var discovered: [EtubuObdDiscoveredDevice] = []
    @Published var isScanning: Bool = false

    var isConnected: Bool { connectionState == .connected }
    var isBusy: Bool {
        switch connectionState {
        case .scanning, .connecting, .reconnecting: return true
        default: return false
        }
    }

    private init() {}

    func applySpeed(kmh: Int, rpm: Int?) {
        self.kmh = max(0, kmh)
        if let rpm { self.rpm = max(0, rpm) }
    }

    func resetLiveValues() {
        kmh = 0
        rpm = 0
        coolantC = nil
        voltageV = nil
        throttlePct = nil
        engineLoadPct = nil
    }
}
