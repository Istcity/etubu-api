import Foundation
import CoreLocation

/// EGM/official vs OSM merge — official wins on same-type proximity conflicts.
enum EtubuHazardMerge {
    /// Same-type dedupe radius (m). Different kinds may coexist.
    static let dedupeMeters: Double = 70

    enum OsmMode {
        /// Outside Turkey or official empty/failed — OSM drives these categories.
        case led
        /// Inside Turkey with good EGM — OSM only fills gaps (never replaces nearby EGM radar/corridor).
        case supplement
    }

    /// Approach / urgent distances (m) for live warnings.
    static func thresholds(for kind: String) -> (warn: Double, urgent: Double) {
        switch kind {
        case "radar", "corridor", "control":
            return (350, 120)
        case "railway":
            return (250, 80)
        case "traffic_light":
            return (100, 35)
        case "stop", "give_way":
            return (80, 25)
        case "crossing", "bump":
            return (60, 20)
        case "charge":
            return (5_000, 400)
        case "weather":
            return (8_000, 1_500)
        default:
            return (350, 120)
        }
    }

    static func stage(for kind: String, distM: Double) -> EtubuWarnStage {
        let t = thresholds(for: kind)
        if distM <= t.urgent { return .critical }
        if distM <= t.warn * 0.55 { return .near }
        if distM <= t.warn { return .mid }
        if distM <= max(t.warn * 1.4, t.warn + 200) { return .far }
        return .idle
    }

    static func isOsmSource(_ h: EtubuRouteHazard) -> Bool {
        h.id.hasPrefix("osm-") || h.id.hasPrefix("osmhz-")
    }

    static func isEnforcement(_ kind: String) -> Bool {
        kind == "radar" || kind == "corridor" || kind == "control"
    }

    static func sameTypeFamily(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        // Stop / yield share family for dedupe.
        let stopFamily: Set = ["stop", "give_way"]
        if stopFamily.contains(a), stopFamily.contains(b) { return true }
        return false
    }

    /// Decide OSM mode from region + whether official enforcement points exist.
    static func osmMode(
        inTurkey: Bool,
        officialAvailable: Bool
    ) -> OsmMode {
        if !inTurkey { return .led }
        if !officialAvailable { return .led }
        return .supplement
    }

    /// Merge OSM into official. Official list is authoritative; OSM never replaces a nearby same-type official point.
    static func merge(
        official: [EtubuRouteHazard],
        osm: [EtubuRouteHazard],
        mode: OsmMode,
        dedupeM: Double = dedupeMeters
    ) -> [EtubuRouteHazard] {
        var out = official
        for cand in osm {
            // Supplement: never place OSM enforcement next to EGM/seed enforcement.
            if mode == .supplement, isEnforcement(cand.kind) {
                let clash = official.contains { o in
                    isEnforcement(o.kind)
                        && distanceM(o, cand) <= dedupeM
                }
                if clash { continue }
            }
            // Any mode: same-type proximity → keep existing (official first).
            if out.contains(where: { existing in
                sameTypeFamily(existing.kind, cand.kind)
                    && distanceM(existing, cand) <= dedupeM
            }) {
                continue
            }
            out.append(cand)
        }
        return out
    }

    /// Prefer official when two same-type points collide (used after flat concat).
    static func dedupePreferOfficial(
        _ list: [EtubuRouteHazard],
        dedupeM: Double = dedupeMeters
    ) -> [EtubuRouteHazard] {
        let sorted = list.sorted { a, b in
            let ao = isOsmSource(a)
            let bo = isOsmSource(b)
            if ao != bo { return !ao && bo } // official first
            return (a.routeIdx ?? 0) < (b.routeIdx ?? 0)
        }
        var out: [EtubuRouteHazard] = []
        for h in sorted {
            if out.contains(where: { existing in
                sameTypeFamily(existing.kind, h.kind)
                    && distanceM(existing, h) <= dedupeM
            }) {
                continue
            }
            out.append(h)
        }
        return out.sorted { ($0.routeIdx ?? 0) < ($1.routeIdx ?? 0) }
    }

    private static func distanceM(_ a: EtubuRouteHazard, _ b: EtubuRouteHazard) -> Double {
        EtubuTrafikAPI.haversineKm(a.lat, a.lng, b.lat, b.lng) * 1000
    }
}
