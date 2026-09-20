import SwiftUI
import CoreLocation

/// Gidilen yolun hız limiti. TR/AB Viyana yuvarlak levha; ABD’de MUTCD dikdörtgen “SPEED LIMIT”.
/// Kaynak sırası: aktif koridor → yakındaki radar/koridor maxspeed → OSM yol limiti.
/// Dururken gizlenir; limit aşımında kırmızı dolar.
struct EtubuRoadSpeedLimitSign: View {
    var size: CGFloat = 36
    @ObservedObject private var osm = EtubuOsmSpeedLimit.shared
    @ObservedObject private var telemetry = EtubuVehicleTelemetry.shared
    @ObservedObject private var demo = EtubuDemoDrive.shared
    @ObservedObject private var warnings = EtubuDriveWarnings.shared

    /// Vienna-style round plate (TR / EU) + US MUTCD “SPEED LIMIT” when GPS is in the United States.
    private static let knownLimits = [20, 30, 40, 50, 60, 70, 80, 82, 90, 100, 110, 120, 130, 140]
    private static let knownMph = [15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80]

    private var isMph: Bool {
        EtubuSpeedUnit.stored.isMph
    }

    private var useMutcd: Bool {
        if let lat = telemetry.latitude, let lng = telemetry.longitude, lat != 0, lng != 0 {
            if EtubuOsmSpeedLimit.isUnitedStates(lat: lat, lng: lng) { return true }
        }
        return isMph || Locale.current.region?.identifier == "US"
    }

    private var currentSpeed: Int {
        demo.isRunning ? demo.displayKmh : telemetry.kmh
    }

    /// Yoldaki hız durumu — öncelik: koridor / yaklaşan radar → OSM.
    private var roadLimit: Int? {
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
        if isMph || useMutcd {
            let mph = Int((Double(lim) / 1.60934).rounded())
            if let near = Self.knownMph.first(where: { abs($0 - mph) <= 2 }) {
                return near
            }
            return min(85, max(5, mph))
        }
        if let near = Self.knownLimits.first(where: { abs($0 - lim) <= 2 }) {
            return near
        }
        return min(160, max(5, lim))
    }

    private var compareLimitKmh: Int? {
        guard let shown = displayLimit else { return nil }
        if isMph || useMutcd {
            return Int((Double(shown) * 1.60934).rounded())
        }
        return shown
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
        guard let lim = compareLimitKmh else { return false }
        return currentSpeed > lim + 3
    }

    var body: some View {
        Group {
            if let limit = displayLimit {
                Group {
                    if useMutcd {
                        signMutcd(limit: limit, over: isOverLimit)
                    } else {
                        signCircle(limit: limit, over: isOverLimit)
                    }
                }
                .accessibilityLabel(
                    isOverLimit
                        ? "Hız limiti aşıldı \(currentSpeed) / \(limit)"
                        : (useMutcd ? "Speed limit \(limit) miles per hour" : "Hız limiti \(limit) kilometre")
                )
            } else {
                Color.clear.frame(width: size, height: size)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 0.2), value: displayLimit)
        .animation(.easeInOut(duration: 0.2), value: useMutcd)
    }

    private func signMutcd(limit: Int, over: Bool) -> some View {
        let w = size * 0.92
        let h = size
        let border = max(1.6, size * 0.055)
        let caption = EtubuClusterL10n.t("speedLimitMutcd")
        let numSize = limit >= 100 ? size * 0.38 : size * 0.46
        let capSize = size * 0.13
        let fill = over ? Color(red: 0.90, green: 0.12, blue: 0.14) : Color.white
        let ink = over ? Color.white : Color.black
        return ZStack {
            RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                .fill(fill)
            RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                .strokeBorder(ink, lineWidth: border)
            VStack(spacing: size * 0.02) {
                Text(caption)
                    .font(.system(size: capSize, weight: .heavy, design: .default))
                    .tracking(size * 0.012)
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .allowsTightening(true)
                Text("\(limit)")
                    .font(.system(size: numSize, weight: .bold, design: .rounded))
                    .foregroundStyle(ink)
                    .monospacedDigit()
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
            }
            .padding(.horizontal, border + 1)
            .padding(.vertical, border)
        }
        .frame(width: w, height: h)
        .shadow(color: .black.opacity(over ? 0.55 : 0.35), radius: over ? 5 : 3, y: 1)
        .scaleEffect(over ? 1.06 : 1.0)
        .animation(.easeInOut(duration: 0.22), value: over)
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
