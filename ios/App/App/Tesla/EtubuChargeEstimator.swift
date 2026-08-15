import Foundation
import CoreLocation

/// Dead-reckons SoC / range between sparse BLE charge snapshots.
/// Anchor = last live Tesla charge. Drain = GPS distance × Wh/km, blended with drive power (kW·dt).
final class EtubuChargeEstimator {
    static let shared = EtubuChargeEstimator()

    private static let whKey = "etubu.charge.whPerKm"

    private var anchorSoc: Double?
    private var anchorRangeKm: Double?
    private var lastFix: CLLocation?
    private var tripKmSinceAnchor: Double = 0
    private var energyKWhSinceAnchor: Double = 0
    private var lastPowerAt: Date?
    private var whPerKm: Double
    private var lastPublishSoc: Int?
    private var lastPublishRange: Int?
    private var lastPublishAt: Date = .distantPast
    private var isCharging = false

    private init() {
        let saved = UserDefaults.standard.double(forKey: Self.whKey)
        whPerKm = (saved >= 80 && saved <= 400) ? saved : 160
    }

    var hasAnchor: Bool { anchorSoc != nil && anchorRangeKm != nil }

    /// Learned / blended consumption for route energy planning.
    var currentWhPerKm: Double { whPerKm }

    func packKWh(soc: Int, rangeKm: Int) -> Double? {
        impliedPackKWh(soc: Double(soc), range: Double(rangeKm))
    }

    /// Live BLE charge — snap display and reset the trip integrator.
    /// `idealRangeKm` (`ideal_battery_range`) is preferred for Wh/km / pack inference.
    func ingestLive(soc: Int, rangeKm: Int, charging: Bool, idealRangeKm: Int? = nil) {
        let modelRange = (idealRangeKm ?? 0) > 0 ? idealRangeKm! : rangeKm
        if tripKmSinceAnchor > 2, let prevSoc = anchorSoc, let prevRange = anchorRangeKm, !charging {
            let usedPct = prevSoc - Double(soc)
            if usedPct > 0.4, let pack = impliedPackKWh(soc: prevSoc, range: prevRange) {
                let usedKWh = pack * usedPct / 100
                let measured = usedKWh * 1000 / tripKmSinceAnchor
                if measured >= 80, measured <= 400 {
                    blendWhPerKm(measured)
                }
            }
        }
        isCharging = charging
        anchorSoc = Double(soc)
        anchorRangeKm = Double(modelRange)
        tripKmSinceAnchor = 0
        energyKWhSinceAnchor = 0
        lastPowerAt = Date()
        lastPublishSoc = soc
        lastPublishRange = rangeKm
        lastPublishAt = Date()
    }

    func ingestCharging(_ charging: Bool) {
        isCharging = charging
    }

    /// Tesla drive power: +kW discharge, −kW regen.
    func ingestPower(kw: Int?, speedKmh: Double, at now: Date = Date()) {
        guard !isCharging else {
            lastPowerAt = now
            return
        }
        guard let kw else {
            lastPowerAt = now
            return
        }
        if let prev = lastPowerAt {
            let dt = now.timeIntervalSince(prev)
            if dt > 0.05, dt < 8 {
                energyKWhSinceAnchor += Double(kw) * dt / 3600.0
            }
        }
        lastPowerAt = now
        if speedKmh > 8, kw > 2 {
            let instant = Double(kw) * 1000.0 / speedKmh
            if instant >= 70, instant <= 420 {
                blendWhPerKm(instant)
            }
        }
        publishIfChanged()
    }

    func ingestOdoDeltaKm(_ km: Double) {
        guard km > 0, km < 5 else { return }
        tripKmSinceAnchor += km
        publishIfChanged()
    }

    func ingestGps(_ loc: CLLocation) {
        guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < 35 else {
            lastFix = loc
            return
        }
        if let prev = lastFix {
            let dt = loc.timestamp.timeIntervalSince(prev.timestamp)
            if dt > 0.2, dt < 8, prev.horizontalAccuracy >= 0, prev.horizontalAccuracy < 45 {
                let km = loc.distance(from: prev) / 1000.0
                if km >= 0.0008, km < 0.35 {
                    tripKmSinceAnchor += km
                }
            }
        }
        lastFix = loc
        publishIfChanged()
    }

    func reset() {
        lastFix = nil
        tripKmSinceAnchor = 0
        energyKWhSinceAnchor = 0
        lastPowerAt = nil
    }

    private func impliedPackKWh(soc: Double, range: Double) -> Double? {
        guard soc >= 5, soc <= 100, range > 8, whPerKm >= 80 else { return nil }
        let remaining = range * whPerKm / 1000.0
        let pack = remaining / (soc / 100.0)
        guard pack >= 30, pack <= 150 else { return nil }
        return pack
    }

    private func blendWhPerKm(_ sample: Double) {
        whPerKm = 0.86 * whPerKm + 0.14 * sample
        UserDefaults.standard.set(whPerKm, forKey: Self.whKey)
    }

    private func estimate() -> (soc: Int, range: Int)? {
        guard let soc = anchorSoc, let range = anchorRangeKm else { return nil }
        if isCharging { return (Int(soc.rounded()), Int(range.rounded())) }
        let pack = impliedPackKWh(soc: soc, range: range)
            ?? max(40, range / max(0.08, soc / 100.0) * whPerKm / 1000.0)
        let usedDist = tripKmSinceAnchor * whPerKm / 1000.0
        let usedEnergy = energyKWhSinceAnchor
        let used: Double = {
            if tripKmSinceAnchor > 0.25, abs(usedEnergy) > 0.04 {
                return 0.6 * usedEnergy + 0.4 * usedDist
            }
            return usedDist
        }()
        let remainingKWh = max(0, pack * soc / 100.0 - used)
        let newSoc = pack > 1 ? remainingKWh / pack * 100.0 : soc
        let newRange = whPerKm > 50 ? remainingKWh * 1000.0 / whPerKm : max(0, range - tripKmSinceAnchor)
        let socI = Int(min(100, max(0, newSoc)).rounded())
        let rangeI = Int(max(0, newRange).rounded())
        return (socI, rangeI)
    }

    private func publishIfChanged() {
        guard let est = estimate() else { return }
        let now = Date()
        let socChanged = lastPublishSoc != est.soc
        let rangeChanged = lastPublishRange.map { abs($0 - est.range) >= 1 } ?? true
        // Integer SoC only; don't spam UI with identical values.
        guard socChanged || rangeChanged else { return }
        if !socChanged, now.timeIntervalSince(lastPublishAt) < 8 { return }
        lastPublishSoc = est.soc
        lastPublishRange = est.range
        lastPublishAt = now
        EtubuVehicleTelemetry.shared.applyEstimatedCharge(soc: est.soc, rangeKm: est.range)
    }
}
