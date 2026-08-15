import Foundation
import CoreLocation
import Combine
import SwiftUI

/// One planned Supercharger / CCS stop on the remaining route.
struct EtubuChargePlanLeg: Identifiable, Equatable {
    var id: String
    var name: String
    var alongKm: Double
    var remainKm: Double
    var arriveSoc: Int
    var departSoc: Int
    var addKwh: Double
    var dwellMin: Int
    var chargerKw: Int
    var hazard: EtubuRouteHazard

    var compactLine: String {
        let along = remainKm >= 10 ? String(format: "%.0f km", remainKm) : String(format: "%.1f km", remainKm)
        return "\(name) · \(along) · \(arriveSoc)→\(departSoc)% · \(dwellMin) dk"
    }
}

/// Full remaining-trip energy budget (Wh/km × distance, optional charge dwell).
struct EtubuEnergyPlan: Equatable {
    var whPerKm: Double
    var packKwh: Double
    var tripKm: Double
    var startSoc: Int
    var destSocUnassisted: Int
    var destSocPlanned: Int
    var kwhToDest: Double
    var legs: [EtubuChargePlanLeg]
    var needsCharge: Bool

    var summaryLine: String {
        if legs.isEmpty {
            return String(format: "%.0f km · %.1f kWh · varış %d%%", tripKm, kwhToDest, destSocPlanned)
        }
        let kwh = legs.reduce(0.0) { $0 + $1.addKwh }
        let min = legs.reduce(0) { $0 + $1.dwellMin }
        return String(format: "%d durak · +%.0f kWh · %d dk · varış %d%%", legs.count, kwh, min, destSocPlanned)
    }
}

/// Hedef varış SoC + durak-durak kWh planı.
@MainActor
final class EtubuEvRoutePlanner: ObservableObject {
    static let shared = EtubuEvRoutePlanner()

    static let targetSocKey = "etubu.ev.targetArrivalSoc"
    private static let reserveSoc = 10
    private static let chargeCapSoc = 80

    @Published var targetArrivalSoc: Int {
        didSet { UserDefaults.standard.set(targetArrivalSoc, forKey: Self.targetSocKey) }
    }

    @Published private(set) var needsCharge = false
    @Published private(set) var suggestedStops: [EtubuRouteHazard] = []
    @Published private(set) var firstChargeAlongKm: Double?
    @Published private(set) var plan: EtubuEnergyPlan?

    private init() {
        let stored = UserDefaults.standard.object(forKey: Self.targetSocKey) as? Int
        targetArrivalSoc = min(90, max(5, stored ?? 20))
    }

    func recompute(
        soc: Int?,
        rangeKm: Int?,
        remainKm: Double?,
        energyAtArrival: Int?,
        chargeHazards: [EtubuRouteHazard]
    ) {
        guard let soc, let rangeKm, rangeKm > 0, let remain = remainKm, remain > 0.4 else {
            clearPlan(arrival: energyAtArrival, soc: soc)
            return
        }

        let est = EtubuChargeEstimator.shared
        let wh = est.currentWhPerKm
        let pack = est.packKWh(soc: soc, rangeKm: rangeKm)
            ?? max(40, Double(rangeKm) / max(0.08, Double(soc) / 100.0) * wh / 1000.0)
        let socPerKm = pack > 1 ? (wh / 1000.0) / pack * 100.0 : Double(soc) / Double(rangeKm)
        let kwhToDest = remain * wh / 1000.0
        let destUnassisted = Int((Double(soc) - remain * socPerKm).rounded())
        let destClamped = max(-20, destUnassisted)

        let totalAlong = max(remain, chargeHazards.compactMap(\.alongKm).max() ?? remain)
        let currentAlong = max(0, totalAlong - remain)
        let destAlong = currentAlong + remain

        var legs: [EtubuChargePlanLeg] = []
        var cursorKm = currentAlong
        var cursorSoc = Double(soc)
        let chargers = chargeHazards
            .filter { ($0.alongKm ?? 0) > currentAlong + 0.8 }
            .sorted { ($0.alongKm ?? 0) < ($1.alongKm ?? 0) }

        let target = Double(targetArrivalSoc)
        while legs.count < 5 {
            let remainAfter = destAlong - cursorKm
            let destArrive = cursorSoc - remainAfter * socPerKm
            if destArrive >= target { break }

            let reachable = chargers.filter { stop in
                guard let along = stop.alongKm, along > cursorKm + 1, along < destAlong - 2 else { return false }
                let arrive = cursorSoc - (along - cursorKm) * socPerKm
                return arrive >= Double(Self.reserveSoc)
            }
            let pick: EtubuRouteHazard? = {
                if let farthest = reachable.max(by: { ($0.alongKm ?? 0) < ($1.alongKm ?? 0) }) {
                    return farthest
                }
                return chargers.first { stop in
                    guard let along = stop.alongKm else { return false }
                    return along > cursorKm + 1 && along < destAlong - 1
                }
            }()
            guard let stop = pick, let along = stop.alongKm else { break }

            let arrive = cursorSoc - (along - cursorKm) * socPerKm
            let arriveSoc = Int(arrive.rounded())
            let remainAfterStop = destAlong - along
            let needForDest = remainAfterStop * socPerKm + target
            var depart = min(Double(Self.chargeCapSoc), max(arrive + 8, needForDest))
            if needForDest > Double(Self.chargeCapSoc) {
                depart = Double(Self.chargeCapSoc)
            }
            depart = min(90, max(Double(arriveSoc + 5), depart))
            if depart <= Double(arriveSoc) { break }

            let addKwh = pack * (depart - Double(arriveSoc)) / 100.0
            let kw = max(50, stop.kw ?? 150)
            let dwell = Self.dwellMinutes(fromSoc: arriveSoc, toSoc: Int(depart.rounded()), packKwh: pack, chargerKw: kw)
            let name = stop.label.isEmpty ? EtubuClusterL10n.t("chargeShort") : stop.label
            legs.append(
                EtubuChargePlanLeg(
                    id: stop.id,
                    name: String(name.prefix(28)),
                    alongKm: along,
                    remainKm: max(0, along - currentAlong),
                    arriveSoc: max(-5, arriveSoc),
                    departSoc: Int(depart.rounded()),
                    addKwh: max(0, addKwh),
                    dwellMin: dwell,
                    chargerKw: kw,
                    hazard: stop
                )
            )
            cursorSoc = depart
            cursorKm = along
        }

        let plannedDest = Int((cursorSoc - (destAlong - cursorKm) * socPerKm).rounded())
        let need = destClamped < targetArrivalSoc
        plan = EtubuEnergyPlan(
            whPerKm: wh,
            packKwh: pack,
            tripKm: remain,
            startSoc: soc,
            destSocUnassisted: destClamped,
            destSocPlanned: max(-5, plannedDest),
            kwhToDest: kwhToDest,
            legs: legs,
            needsCharge: need
        )
        needsCharge = need
        suggestedStops = legs.map(\.hazard)
        firstChargeAlongKm = legs.first?.remainKm
    }

    func refreshFromLiveState() {
        let t = EtubuVehicleTelemetry.shared
        let w = EtubuDriveWarnings.shared
        let charges = (w.remainingHazards.isEmpty ? w.hazards : w.remainingHazards)
            .filter { $0.kind == "charge" }
        recompute(
            soc: t.displaySocPercent ?? t.socPercent,
            rangeKm: t.displayRangeKm ?? t.rangeKm,
            remainKm: t.effectiveRemainKm,
            energyAtArrival: t.energyAtArrivalPercent,
            chargeHazards: charges
        )
        t.needsChargeStop = needsCharge
        t.suggestedChargeCount = suggestedStops.count
        t.nextChargeAlongKm = firstChargeAlongKm
        if let planned = plan?.destSocPlanned, needsCharge {
            let next = max(0, planned)
            if t.energyAtArrivalPercent != next {
                t.energyAtArrivalPercent = next
            }
        }
    }

    private func clearPlan(arrival: Int?, soc: Int?) {
        needsCharge = (arrival ?? 100) < targetArrivalSoc
        suggestedStops = []
        firstChargeAlongKm = nil
        plan = nil
        let t = EtubuVehicleTelemetry.shared
        t.needsChargeStop = needsCharge
        t.suggestedChargeCount = 0
        t.nextChargeAlongKm = nil
    }

    /// Tapered DC dwell: faster below 50%, slower above.
    static func dwellMinutes(fromSoc: Int, toSoc: Int, packKwh: Double, chargerKw: Int) -> Int {
        let add = packKwh * Double(max(1, toSoc - fromSoc)) / 100.0
        let mid = Double(fromSoc + toSoc) / 2.0
        let taper: Double
        if mid < 20 { taper = 0.92 }
        else if mid < 50 { taper = 0.72 }
        else if mid < 80 { taper = 0.42 }
        else { taper = 0.20 }
        let kw = max(40.0, Double(chargerKw)) * taper
        return max(3, Int((add / kw * 60.0).rounded()))
    }
}

// MARK: - Cluster / settings card

struct EtubuEnergyPlanCard: View {
    var plan: EtubuEnergyPlan
    var compact: Bool = false
    var accent: Color
    var muted: Color
    var primary: Color
    var onStop: ((EtubuChargePlanLeg) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 8) {
            HStack(spacing: 6) {
                Image(systemName: plan.needsCharge ? "bolt.car.fill" : "leaf.fill")
                    .font(.system(size: compact ? 10 : 12, weight: .bold))
                    .foregroundStyle(plan.needsCharge ? Color.orange : accent)
                Text(plan.needsCharge ? EtubuClusterL10n.t("evPlanStops") : EtubuClusterL10n.t("evPlanClear"))
                    .font(EtubuClusterFonts.ui(compact ? 10 : 12, weight: .heavy))
                    .foregroundStyle(plan.needsCharge ? Color.orange : muted)
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Text(String(format: "%.0f Wh/km", plan.whPerKm))
                    .font(EtubuClusterFonts.ui(compact ? 10 : 11, weight: .semibold))
                    .foregroundStyle(muted)
                    .lineLimit(1)
            }
            .accessibilityIdentifier("etubu.ev.chargeSuggest")

            Text(plan.summaryLine)
                .font(EtubuClusterFonts.ui(compact ? 11 : 13, weight: .semibold))
                .foregroundStyle(primary.opacity(0.9))
                .lineLimit(compact ? 2 : 3)
                .minimumScaleFactor(0.75)
                .fixedSize(horizontal: false, vertical: true)

            if !compact {
                HStack(spacing: 10) {
                    metric(EtubuClusterL10n.t("evPlanPack"), String(format: "%.0f kWh", plan.packKwh))
                    metric(EtubuClusterL10n.t("evPlanTripKwh"), String(format: "%.1f kWh", plan.kwhToDest))
                    metric(
                        EtubuClusterL10n.t("evPlanDestSoc"),
                        "\(max(0, plan.destSocPlanned))%"
                    )
                }
            }

            ForEach(plan.legs.prefix(compact ? 2 : 5)) { leg in
                Button {
                    onStop?(leg)
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(leg.name)
                                .font(EtubuClusterFonts.ui(compact ? 11 : 13, weight: .semibold))
                                .foregroundStyle(primary.opacity(0.92))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(leg.compactLine.replacingOccurrences(of: "\(leg.name) · ", with: ""))
                                .font(EtubuClusterFonts.ui(compact ? 10 : 11, weight: .medium))
                                .foregroundStyle(muted)
                                .lineLimit(2)
                                .minimumScaleFactor(0.7)
                        }
                        Spacer(minLength: 0)
                        Text(String(format: "+%.0f kWh", leg.addKwh))
                            .font(EtubuClusterFonts.gauge(compact ? 11 : 13))
                            .foregroundStyle(accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(EtubuClusterL10n.t("openInMaps"))
            }
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(EtubuClusterFonts.ui(9, weight: .medium))
                .foregroundStyle(muted)
                .lineLimit(1)
            Text(value)
                .font(EtubuClusterFonts.ui(12, weight: .bold))
                .foregroundStyle(primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
