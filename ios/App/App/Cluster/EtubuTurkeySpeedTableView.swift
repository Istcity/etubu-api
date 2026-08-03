import SwiftUI
import CoreLocation

/// Gidilen yolun hız limiti — yalnızca TR tarzı yuvarlak levha ikonu (Tesla tarzı).
/// Kaynak sırası: aktif koridor → yakındaki radar/koridor maxspeed → OSM yol limiti.
/// Dururken gizlenir; limit aşımında kırmızı dolar.
struct EtubuRoadSpeedLimitSign: View {
    var size: CGFloat = 36
    @ObservedObject private var osm = EtubuOsmSpeedLimit.shared
    @ObservedObject private var telemetry = EtubuVehicleTelemetry.shared
    @ObservedObject private var demo = EtubuDemoDrive.shared
    @ObservedObject private var warnings = EtubuDriveWarnings.shared

    /// Yaygın TR limitleri + ara değerler (ör. 82).
    private static let knownLimits = [20, 30, 40, 50, 60, 70, 80, 82, 90, 100, 110, 120, 130, 140]

    private var currentSpeed: Int {
        demo.isRunning ? demo.displayKmh : telemetry.kmh
    }

    /// Yoldaki hız durumu — öncelik: koridor / yaklaşan radar → OSM.
    private var roadLimit: Int? {
        guard currentSpeed >= EtubuOsmSpeedLimit.movingKmhThreshold else { return nil }

        if warnings.corridorActive, let lim = warnings.corridorLimit, lim > 0 {
            return lim
        }
        if let ahead = nearestEnforcementLimit {
            return ahead
        }
        guard let lim = osm.limitKmh, lim > 0 else { return nil }
        return lim
    }

    private var displayLimit: Int? {
        guard let lim = roadLimit else { return nil }
        if let near = Self.knownLimits.first(where: { abs($0 - lim) <= 2 }) {
            return near
        }
        return min(160, max(5, lim))
    }

    /// 2.5 km içindeki radar / hız koridoru levha limiti.
    private var nearestEnforcementLimit: Int? {
        var pool = warnings.remainingHazards.isEmpty ? warnings.hazards : warnings.remainingHazards
        let live = EtubuLiveRadarMonitor.shared.cameras
        if pool.isEmpty {
            pool = live
        } else if !live.isEmpty {
            var seen = Set(pool.map(\.id))
            for c in live where !seen.contains(c.id) {
                pool.append(c)
                seen.insert(c.id)
            }
        }
        guard !pool.isEmpty else { return nil }
        guard let lat = telemetry.latitude, let lng = telemetry.longitude else { return nil }

        var best: (dM: Double, lim: Int)?
        for h in pool {
            guard h.kind == "radar" || h.kind == "corridor" else { continue }
            guard let lim = h.maxspeed, lim > 0 else { continue }
            let dM = Self.haversineM(lat, lng, h.lat, h.lng)
            guard dM <= 2500 else { continue }
            if best == nil || dM < best!.dM {
                best = (dM, lim)
            }
        }
        return best?.lim
    }

    private var isOverLimit: Bool {
        guard let lim = displayLimit else { return false }
        return currentSpeed > lim + 5
    }

    var body: some View {
        Group {
            if let limit = displayLimit {
                signCircle(limit: limit, over: isOverLimit)
                    .accessibilityLabel(
                        isOverLimit
                            ? "Hız limiti aşıldı \(currentSpeed) / \(limit)"
                            : "Hız limiti \(limit) kilometre"
                    )
            } else {
                Color.clear.frame(width: size, height: size)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 0.2), value: displayLimit)
    }

    private func signCircle(limit: Int, over: Bool) -> some View {
        let ring = max(2.4, size * 0.11)
        let fontSize = limit >= 100 ? size * 0.38 : size * 0.44
        let accent = Color(red: 0.90, green: 0.12, blue: 0.14)
        return ZStack {
            Circle()
                .fill(over ? accent : Color.white)
            Circle()
                .strokeBorder(accent, lineWidth: ring)
            Text("\(limit)")
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .foregroundStyle(over ? Color.white : .black)
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .shadow(color: .black.opacity(over ? 0.55 : 0.35), radius: over ? 5 : 3, y: 1)
        .scaleEffect(over ? 1.06 : 1.0)
        .animation(.easeInOut(duration: 0.22), value: over)
    }

    private static func haversineM(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        EtubuTrafikAPI.haversineKm(lat1, lon1, lat2, lon2) * 1000
    }
}
