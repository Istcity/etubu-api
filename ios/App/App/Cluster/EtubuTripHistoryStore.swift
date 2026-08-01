import Foundation
import UIKit

/// Yolculuk geçmişi — odo / mesafe / ortalama hız / yaklaşık Wh/km.
struct EtubuTripRecord: Codable, Identifiable, Equatable {
    var id: String
    var startedAt: Date
    var endedAt: Date?
    var startOdoKm: Int?
    var endOdoKm: Int?
    var distanceKm: Double
    var maxKmh: Int
    var avgKmh: Double
    var routeTo: String
    /// Yaklaşık net enerji (kWh) — powerHistory örneklerinden.
    var energyKwh: Double?
    var whPerKm: Double?

    var durationMinutes: Int {
        let end = endedAt ?? Date()
        return max(1, Int(end.timeIntervalSince(startedAt) / 60))
    }
}

@MainActor
final class EtubuTripHistoryStore: ObservableObject {
    static let shared = EtubuTripHistoryStore()
    private static let storageKey = "etubu.trips.v1"
    private static let maxTrips = 80

    @Published private(set) var trips: [EtubuTripRecord] = []
    @Published private(set) var active: EtubuTripRecord?

    private var samplePowerSum: Double = 0
    private var samplePowerCount: Int = 0
    private var lastGear: String = "P"

    private init() {
        trips = Self.load()
    }

    func noteTelemetry(kmh: Int, gear: String, odo: Int?, powerKw: Int?, routeTo: String) {
        let g = gear.uppercased()
        // D’ye geçiş → trip başlat
        if ["D", "R", "N"].contains(g), active == nil, kmh >= 5 {
            start(odo: odo, routeTo: routeTo)
        }
        // P + yavaş → trip bitir
        if g == "P", let cur = active, kmh < 3 {
            end(odo: odo)
        }
        lastGear = g
        guard var cur = active else { return }
        cur.maxKmh = max(cur.maxKmh, kmh)
        if let odo, let start = cur.startOdoKm, odo >= start {
            cur.distanceKm = Double(odo - start)
        } else {
            // odo yoksa süre × hız kabaca
            let mins = max(1.0, Date().timeIntervalSince(cur.startedAt) / 60)
            cur.avgKmh = Double(kmh)
            if cur.distanceKm <= 0 {
                cur.distanceKm = max(cur.distanceKm, (mins / 60.0) * Double(max(kmh, 1)))
            }
        }
        if let p = powerKw {
            samplePowerSum += Double(p)
            samplePowerCount += 1
        }
        active = cur
    }

    func start(odo: Int?, routeTo: String) {
        guard active == nil else { return }
        samplePowerSum = 0
        samplePowerCount = 0
        active = EtubuTripRecord(
            id: UUID().uuidString,
            startedAt: Date(),
            endedAt: nil,
            startOdoKm: odo,
            endOdoKm: nil,
            distanceKm: 0,
            maxKmh: 0,
            avgKmh: 0,
            routeTo: routeTo,
            energyKwh: nil,
            whPerKm: nil
        )
    }

    func end(odo: Int?) {
        guard var cur = active else { return }
        cur.endedAt = Date()
        cur.endOdoKm = odo
        if let start = cur.startOdoKm, let end = odo, end >= start {
            cur.distanceKm = Double(end - start)
        }
        let mins = max(1.0, cur.endedAt!.timeIntervalSince(cur.startedAt) / 60.0)
        if cur.distanceKm > 0.1 {
            cur.avgKmh = cur.distanceKm / (mins / 60.0)
        }
        if samplePowerCount > 0, cur.distanceKm > 0.1 {
            // Ortalama kW × saat ≈ kWh (kaba)
            let avgKw = samplePowerSum / Double(samplePowerCount)
            let hours = mins / 60.0
            let kwh = abs(avgKw) * hours
            cur.energyKwh = kwh
            cur.whPerKm = (kwh * 1000) / cur.distanceKm
        }
        trips.insert(cur, at: 0)
        if trips.count > Self.maxTrips { trips = Array(trips.prefix(Self.maxTrips)) }
        Self.save(trips)
        active = nil
    }

    func clearAll() {
        trips = []
        active = nil
        Self.save([])
    }

    // MARK: - Analytics (P3)

    struct AnalyticsSummary: Equatable {
        var tripCount: Int
        var totalDistanceKm: Double
        var totalEnergyKwh: Double
        var avgWhPerKm: Double?
        var bestWhPerKm: Double?
        var last7DayKm: Double
        var last7DayAvgWh: Double?
    }

    var analytics: AnalyticsSummary {
        let finished = trips.filter { $0.endedAt != nil && $0.distanceKm > 0.05 }
        let totalKm = finished.reduce(0.0) { $0 + $1.distanceKm }
        let withEnergy = finished.compactMap { t -> (Double, Double)? in
            guard let wh = t.whPerKm, wh > 0, t.distanceKm > 0.05 else { return nil }
            return (wh, t.distanceKm)
        }
        let totalKwh = finished.compactMap(\.energyKwh).reduce(0.0, +)
        let weightedWh: Double? = {
            guard !withEnergy.isEmpty else { return nil }
            let sumWhKm = withEnergy.reduce(0.0) { $0 + $1.0 * $1.1 }
            let sumKm = withEnergy.reduce(0.0) { $0 + $1.1 }
            guard sumKm > 0 else { return nil }
            return sumWhKm / sumKm
        }()
        let best = withEnergy.map(\.0).min()
        let weekAgo = Date().addingTimeInterval(-7 * 24 * 3600)
        let week = finished.filter { $0.startedAt >= weekAgo }
        let weekKm = week.reduce(0.0) { $0 + $1.distanceKm }
        let weekWhSamples = week.compactMap { t -> (Double, Double)? in
            guard let wh = t.whPerKm, wh > 0 else { return nil }
            return (wh, t.distanceKm)
        }
        let weekAvg: Double? = {
            guard !weekWhSamples.isEmpty else { return nil }
            let s = weekWhSamples.reduce(0.0) { $0 + $1.0 * $1.1 }
            let k = weekWhSamples.reduce(0.0) { $0 + $1.1 }
            return k > 0 ? s / k : nil
        }()
        return AnalyticsSummary(
            tripCount: finished.count,
            totalDistanceKm: totalKm,
            totalEnergyKwh: totalKwh,
            avgWhPerKm: weightedWh,
            bestWhPerKm: best,
            last7DayKm: weekKm,
            last7DayAvgWh: weekAvg
        )
    }

    /// Recent finished trips with Wh/km for chart bars (oldest → newest, max 12).
    var whPerKmSeries: [(id: String, label: String, whPerKm: Double)] {
        let df = DateFormatter()
        df.dateFormat = "d MMM"
        return trips
            .filter { $0.endedAt != nil }
            .compactMap { t -> (String, String, Double)? in
                guard let wh = t.whPerKm, wh > 0 else { return nil }
                return (t.id, df.string(from: t.startedAt), wh)
            }
            .prefix(12)
            .reversed()
            .map { ($0.0, $0.1, $0.2) }
    }

    func exportCSV() -> URL? {
        var lines = ["id,started,ended,distance_km,max_kmh,avg_kmh,wh_per_km,route"]
        let df = ISO8601DateFormatter()
        for t in trips {
            let start = df.string(from: t.startedAt)
            let end = t.endedAt.map { df.string(from: $0) } ?? ""
            let wh = t.whPerKm.map { String(format: "%.0f", $0) } ?? ""
            let route = t.routeTo.replacingOccurrences(of: ",", with: " ")
            lines.append("\(t.id),\(start),\(end),\(String(format: "%.1f", t.distanceKm)),\(t.maxKmh),\(String(format: "%.0f", t.avgKmh)),\(wh),\(route)")
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("etubu-trips.csv")
        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private static func load() -> [EtubuTripRecord] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([EtubuTripRecord].self, from: data)
        else { return [] }
        return decoded
    }

    private static func save(_ trips: [EtubuTripRecord]) {
        if let data = try? JSONEncoder().encode(trips) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
