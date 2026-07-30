import Foundation
import Combine
import CoreLocation

enum EtubuVehicleSource: String {
    case tesla
    case obd
    case gps
    case none
}

enum EtubuVehicleConnectionState: String {
    case idle
    case needsVIN
    case pairing
    case waitingForCard
    case connecting
    case connected
    case reconnecting
    case disconnected
    case failed
}

struct EtubuTireReading: Equatable {
    var psi: Double?
    var warning: Bool
}

/// Unified live vehicle state for the single-screen cluster (Tesla primary, OBD fallback).
final class EtubuVehicleTelemetry: ObservableObject {
    static let shared = EtubuVehicleTelemetry()

    @Published var connectionState: EtubuVehicleConnectionState = .needsVIN
    @Published var source: EtubuVehicleSource = .none
    @Published var deviceLabel: String = "Tesla"
    @Published var statusMessage: String = "Enter VIN to pair"
    @Published var vin: String = ""
    @Published var lastUpdateAt: Date?

    // Drive
    @Published var kmh: Int = 0
    @Published var gear: String = "P"
    @Published var powerKw: Int?
    @Published var powerHistory: [Int] = [] // last ~40 samples for sparkline
    @Published var odometerKm: Int?

    // Charge
    @Published var socPercent: Int?
    @Published var rangeKm: Int?
    @Published var chargeKw: Int?
    @Published var isCharging: Bool = false
    @Published var chargeLimitPercent: Int?
    @Published var chargerAmps: Int?
    @Published var chargerVolts: Int?
    @Published var minutesToFullCharge: Int?
    @Published var chargePortOpen: Bool?

    // Climate
    @Published var outsideC: Double?
    @Published var insideC: Double?
    @Published var climateOn: Bool?

    // Vehicle nav (Tesla active route)
    @Published var navDestination: String = ""
    @Published var navRemainKm: Double?
    @Published var navEtaMinutes: Double?
    @Published var energyAtArrivalPercent: Int?

    // Cap RouteGuard trip
    @Published var routeActive: Bool = false
    @Published var routeFrom: String = ""
    @Published var routeTo: String = ""

    // TPMS (psi)
    @Published var tpmsFL = EtubuTireReading(psi: nil, warning: false)
    @Published var tpmsFR = EtubuTireReading(psi: nil, warning: false)
    @Published var tpmsRL = EtubuTireReading(psi: nil, warning: false)
    @Published var tpmsRR = EtubuTireReading(psi: nil, warning: false)

    // Closures
    @Published var locked: Bool?
    @Published var doorFLOpen: Bool?
    @Published var doorFROpen: Bool?
    @Published var doorRLOpen: Bool?
    @Published var doorRROpen: Bool?
    @Published var frunkOpen: Bool?
    @Published var trunkOpen: Bool?
    @Published var sentryActive: Bool?
    @Published var valetMode: Bool?
    @Published var userPresent: Bool?

    // Media
    @Published var mediaTitle: String = ""
    @Published var mediaArtist: String = ""
    @Published var mediaAlbum: String = ""
    @Published var mediaSource: String = ""

    // Map (phone GPS fallback — Tesla location not in swift-tesla-ble snapshot)
    @Published var latitude: Double?
    @Published var longitude: Double?
    @Published var headingDeg: Double?

    // OBD-only extras
    @Published var rpm: Int = 0
    @Published var coolantC: Int?
    @Published var voltageV: Double?

    private init() {
        if let saved = EtubuTeslaVinStore.vin {
            vin = saved
            connectionState = .idle
            statusMessage = "Ready · \(String(saved.suffix(6)))"
            deviceLabel = "Tesla \(String(saved.suffix(6)))"
        }
    }

    var isLiveTesla: Bool { source == .tesla && connectionState == .connected }

    var anyDoorOpen: Bool {
        [doorFLOpen, doorFROpen, doorRLOpen, doorRROpen, frunkOpen, trunkOpen]
            .contains { $0 == true }
    }

    var connectionFreshnessSeconds: TimeInterval? {
        guard let lastUpdateAt else { return nil }
        return Date().timeIntervalSince(lastUpdateAt)
    }

    var connectionQualityLabel: String {
        guard connectionState == .connected else { return connectionState.rawValue }
        guard let s = connectionFreshnessSeconds else { return "Bağlı" }
        if s < 3 { return "Canlı" }
        if s < 8 { return "İyi" }
        if s < 20 { return "Gecikmeli" }
        return "Zayıf"
    }

    func applyTeslaDrive(
        kmh: Int,
        gear: String,
        powerKw: Int?,
        odometerKm: Int?,
        navDestination: String?,
        navRemainKm: Double?,
        navEtaMinutes: Double?
    ) {
        self.kmh = max(0, kmh)
        self.gear = gear
        self.powerKw = powerKw
        if let powerKw {
            var hist = powerHistory
            hist.append(powerKw)
            if hist.count > 40 { hist.removeFirst(hist.count - 40) }
            powerHistory = hist
        }
        if let odometerKm { self.odometerKm = odometerKm }
        if let navDestination { self.navDestination = navDestination }
        if let navRemainKm { self.navRemainKm = navRemainKm }
        if let navEtaMinutes { self.navEtaMinutes = navEtaMinutes }
        recomputeEnergyAtArrival()
        self.source = .tesla
        lastUpdateAt = Date()
    }

    func applyTeslaCharge(
        soc: Int?,
        rangeKm: Int?,
        chargeKw: Int?,
        charging: Bool,
        limitPercent: Int?,
        amps: Int?,
        volts: Int?,
        minutesToFull: Int?,
        portOpen: Bool?
    ) {
        if let soc { socPercent = soc }
        if let rangeKm { self.rangeKm = rangeKm }
        self.chargeKw = chargeKw
        isCharging = charging
        if let limitPercent { chargeLimitPercent = limitPercent }
        if let amps { chargerAmps = amps }
        if let volts { chargerVolts = volts }
        if let minutesToFull { minutesToFullCharge = minutesToFull }
        if let portOpen { chargePortOpen = portOpen }
        recomputeEnergyAtArrival()
        lastUpdateAt = Date()
    }

    func applyTeslaClimate(outsideC: Double?, insideC: Double?, climateOn: Bool?) {
        if let outsideC { self.outsideC = outsideC }
        if let insideC { self.insideC = insideC }
        if let climateOn { self.climateOn = climateOn }
        lastUpdateAt = Date()
    }

    func applyTeslaTPMS(fl: EtubuTireReading, fr: EtubuTireReading, rl: EtubuTireReading, rr: EtubuTireReading) {
        tpmsFL = fl
        tpmsFR = fr
        tpmsRL = rl
        tpmsRR = rr
        lastUpdateAt = Date()
    }

    func applyTeslaClosures(
        locked: Bool?,
        fl: Bool?, fr: Bool?, rl: Bool?, rr: Bool?,
        frunk: Bool?, trunk: Bool?,
        sentry: Bool?, valet: Bool?, present: Bool?
    ) {
        self.locked = locked
        doorFLOpen = fl
        doorFROpen = fr
        doorRLOpen = rl
        doorRROpen = rr
        frunkOpen = frunk
        trunkOpen = trunk
        sentryActive = sentry
        valetMode = valet
        userPresent = present
        lastUpdateAt = Date()
    }

    func applyTeslaMedia(title: String?, artist: String?, album: String?, sourceName: String?) {
        if let title { mediaTitle = title }
        if let artist { mediaArtist = artist }
        if let album { mediaAlbum = album }
        if let sourceName { mediaSource = sourceName }
        lastUpdateAt = Date()
    }

    func applyMapLocation(lat: Double?, lng: Double?, heading: Double?) {
        if let lat { latitude = lat }
        if let lng { longitude = lng }
        if let heading { headingDeg = heading }
    }

    func applyObdFallback(kmh: Int, rpm: Int, coolant: Int?, voltage: Double?) {
        guard !isLiveTesla else { return }
        self.kmh = max(0, kmh)
        self.rpm = max(0, rpm)
        self.coolantC = coolant
        self.voltageV = voltage
        self.source = .obd
        lastUpdateAt = Date()
        if connectionState != .connected && connectionState != .connecting && connectionState != .pairing {
            connectionState = .connected
            deviceLabel = "OBD"
            statusMessage = "OBD fallback"
        }
    }

    private func recomputeEnergyAtArrival() {
        guard let soc = socPercent, let range = rangeKm, range > 0, let rem = navRemainKm, rem > 0 else {
            // Fallback: show current SOC when no nav remain
            if navRemainKm == nil || (navRemainKm ?? 0) <= 0 {
                energyAtArrivalPercent = socPercent
            }
            return
        }
        let used = min(1.0, rem / Double(range))
        energyAtArrivalPercent = max(0, Int((Double(soc) * (1.0 - used)).rounded()))
    }

    static func barToPsi(_ bar: Double?) -> Double? {
        guard let bar else { return nil }
        return bar * 14.5038
    }

    var arrivalTimeLabel: String {
        guard let mins = navEtaMinutes, mins >= 0 else { return "—" }
        let date = Date().addingTimeInterval(mins * 60)
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    var navRemainLabel: String {
        guard let km = navRemainKm else { return "—" }
        if km >= 10 { return String(format: "%.0f km", km) }
        return String(format: "%.1f km", km)
    }
}
