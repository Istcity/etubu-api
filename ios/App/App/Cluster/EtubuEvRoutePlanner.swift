import Foundation
import CoreLocation
import Combine

/// Hedef varış SoC + rota üzerindeki şarj önerileri.
@MainActor
final class EtubuEvRoutePlanner: ObservableObject {
    static let shared = EtubuEvRoutePlanner()

    static let targetSocKey = "etubu.ev.targetArrivalSoc"

    /// Varışta istenen minimum SoC (varsayılan %20).
    @Published var targetArrivalSoc: Int {
        didSet { UserDefaults.standard.set(targetArrivalSoc, forKey: Self.targetSocKey) }
    }

    @Published private(set) var needsCharge = false
    @Published private(set) var suggestedStops: [EtubuRouteHazard] = []
    @Published private(set) var firstChargeAlongKm: Double?

    private init() {
        let stored = UserDefaults.standard.object(forKey: Self.targetSocKey) as? Int
        targetArrivalSoc = min(90, max(5, stored ?? 20))
    }

    /// Rota hazard’larından (kind=charge) SoC bütçesine göre öneri seç.
    func recompute(
        soc: Int?,
        rangeKm: Int?,
        remainKm: Double?,
        energyAtArrival: Int?,
        chargeHazards: [EtubuRouteHazard]
    ) {
        let target = targetArrivalSoc
        let arrival = energyAtArrival
        let below = (arrival ?? 100) < target
        needsCharge = below

        guard below, let soc, let rangeKm, rangeKm > 0 else {
            suggestedStops = []
            firstChargeAlongKm = nil
            return
        }

        let tripKm = remainKm ?? chargeHazards.compactMap(\.alongKm).max() ?? 0
        guard tripKm > 0 else {
            suggestedStops = []
            firstChargeAlongKm = nil
            return
        }

        // km başına SoC yaklaşık tüketim
        let socPerKm = Double(soc) / Double(rangeKm)
        var projected = Double(soc)
        var picks: [EtubuRouteHazard] = []
        let sorted = chargeHazards
            .filter { ($0.alongKm ?? 0) > 0.5 }
            .sorted { ($0.alongKm ?? 0) < ($1.alongKm ?? 0) }

        var lastAlong = 0.0
        for stop in sorted {
            let along = stop.alongKm ?? 0
            let segment = max(0, along - lastAlong)
            projected -= segment * socPerKm
            // Şarja inmeden önce hedef altına düşeceksek bu durağı öner.
            if projected < Double(target) + 5 {
                picks.append(stop)
                // Basit model: durakta +40% SoC (hızlı şarj varsayımı, tavan 90).
                projected = min(90, projected + 40)
                lastAlong = along
            }
            if picks.count >= 4 { break }
            if projected - (tripKm - along) * socPerKm >= Double(target) { break }
        }

        suggestedStops = picks
        firstChargeAlongKm = picks.first?.alongKm
    }

    func refreshFromLiveState() {
        let t = EtubuVehicleTelemetry.shared
        let w = EtubuDriveWarnings.shared
        let charges = (w.remainingHazards.isEmpty ? w.hazards : w.remainingHazards)
            .filter { $0.kind == "charge" }
        recompute(
            soc: t.socPercent,
            rangeKm: t.rangeKm,
            remainKm: t.effectiveRemainKm,
            energyAtArrival: t.energyAtArrivalPercent,
            chargeHazards: charges
        )
        t.needsChargeStop = needsCharge
        t.suggestedChargeCount = suggestedStops.count
        t.nextChargeAlongKm = firstChargeAlongKm
    }
}
