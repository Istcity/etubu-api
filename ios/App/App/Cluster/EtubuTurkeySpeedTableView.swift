import SwiftUI

/// Gidilen yolun hız limiti — yalnızca TR tarzı yuvarlak levha ikonu (Tesla tarzı).
/// Metin / tablo yok; OSM’den gelen limit gösterilir. Dururken gizlenir.
struct EtubuRoadSpeedLimitSign: View {
    var size: CGFloat = 36
    @ObservedObject private var osm = EtubuOsmSpeedLimit.shared
    @ObservedObject private var telemetry = EtubuVehicleTelemetry.shared
    @ObservedObject private var demo = EtubuDemoDrive.shared

    /// Yaygın TR limitleri + ara değerler (ör. 82).
    private static let knownLimits = [20, 30, 40, 50, 60, 70, 80, 82, 90, 100, 110, 120, 130, 140]

    private var displayLimit: Int? {
        // Araç hareket etmeden levha gösterme (demo + canlı).
        let speed = demo.isRunning ? demo.displayKmh : telemetry.kmh
        guard speed >= EtubuOsmSpeedLimit.movingKmhThreshold else { return nil }
        guard let lim = osm.limitKmh, lim > 0 else { return nil }
        // Bilinen levhaya ±2 km yakınsa o levha; değilse olduğu gibi
        if let near = Self.knownLimits.first(where: { abs($0 - lim) <= 2 }) {
            return near
        }
        return min(160, max(5, lim))
    }

    var body: some View {
        Group {
            if let limit = displayLimit {
                signCircle(limit: limit)
                    .accessibilityLabel("Hız limiti \(limit) kilometre")
            } else {
                // Limit yokken boş yer tutma — gizle
                Color.clear.frame(width: size, height: size)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: size, height: size)
    }

    private func signCircle(limit: Int) -> some View {
        let ring = max(2.4, size * 0.11)
        let fontSize = limit >= 100 ? size * 0.38 : size * 0.44
        return ZStack {
            Circle()
                .fill(Color.white)
            Circle()
                .strokeBorder(Color(red: 0.90, green: 0.12, blue: 0.14), lineWidth: ring)
            Text("\(limit)")
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
    }
}
