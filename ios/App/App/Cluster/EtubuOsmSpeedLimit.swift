import Foundation
import CoreLocation
import Combine

/// OpenStreetMap Overpass — yakındaki yolun maxspeed değeri (küresel; levha etiketi öncelikli).
@MainActor
final class EtubuOsmSpeedLimit: ObservableObject {
    static let shared = EtubuOsmSpeedLimit()

    @Published var limitKmh: Int?
    @Published var highway: String?
    @Published var roadName: String?
    @Published var lastError: String?
    /// Demo / manuel override — OSM sorgusunu geçersiz kılar.
    @Published private(set) var demoOverride = false

    private var lastSuccessAt: Date?
    private var lastSuccessCoord: CLLocationCoordinate2D?
    private var lastAttemptAt: Date?
    private var task: Task<Void, Never>?

    private let endpoints = [
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
    ]

    /// Yaygın TR hız limit levhaları (gösterim eşlemesi için).
    static let standardLimits = [20, 30, 40, 50, 60, 70, 80, 82, 90, 100, 110, 120, 130, 140]
    /// Araç bu hızın altındayken levha gösterilmez / OSM çekilmez.
    static let movingKmhThreshold = 5

    /// Demo: levhayı doğrudan ayarla (OSM beklemeden).
    func applyDemoLimit(_ kmh: Int?, highway: String? = nil) {
        demoOverride = true
        limitKmh = kmh
        self.highway = highway
        roadName = kmh != nil ? "Demo yol" : nil
        lastError = nil
    }

    func clearDemoOverride() {
        demoOverride = false
        clearLiveLimit()
    }

    /// Canlı OSM levhasını temizle (park / durma / fail).
    func clearLiveLimit() {
        task?.cancel()
        task = nil
        limitKmh = nil
        highway = nil
        roadName = nil
        lastError = nil
    }

    func refreshIfNeeded(lat: Double?, lng: Double?, speedKmh: Int = 0) {
        guard !demoOverride else { return }
        // Dururken levha yok — önceki OSM sonucunu da sil.
        guard speedKmh >= Self.movingKmhThreshold else {
            if limitKmh != nil || highway != nil || roadName != nil {
                clearLiveLimit()
            } else {
                task?.cancel()
                task = nil
            }
            return
        }
        guard let lat, let lng, lat != 0, lng != 0 else { return }
        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lng)

        // Success cache: aynı noktada sık sorgu yok.
        if let last = lastSuccessCoord, let at = lastSuccessAt {
            let moved = CLLocation(latitude: last.latitude, longitude: last.longitude)
                .distance(from: CLLocation(latitude: lat, longitude: lng))
            if moved < 80, Date().timeIntervalSince(at) < 25 { return }
        }
        // Fail / in-flight cooldown — stamp only after success (no stale lock).
        if let at = lastAttemptAt, Date().timeIntervalSince(at) < 8 { return }

        lastAttemptAt = Date()
        task?.cancel()
        task = Task { await fetch(lat: lat, lng: lng, coord: coord) }
    }

    private func fetch(lat: Double, lng: Double, coord: CLLocationCoordinate2D) async {
        guard !demoOverride else { return }
        let q = """
        [out:json][timeout:12];
        way(around:60,\(lat),\(lng))["highway"]["highway"!~"footway|path|steps|cycleway|pedestrian|track|service"];
        out tags center 8;
        """
        var lastFail: String?
        for urlStr in endpoints {
            if Task.isCancelled || demoOverride { return }
            guard let url = URL(string: urlStr) else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
            req.httpBody = "data=\(q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q)".data(using: .utf8)
            req.timeoutInterval = 14
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    lastFail = "HTTP \((resp as? HTTPURLResponse)?.statusCode ?? -1)"
                    continue
                }
                if let parsed = Self.parse(data) {
                    guard !demoOverride else { return }
                    guard EtubuVehicleTelemetry.shared.kmh >= Self.movingKmhThreshold else { return }
                    limitKmh = parsed.limit
                    highway = parsed.highway
                    roadName = parsed.name
                    lastError = nil
                    lastSuccessCoord = coord
                    lastSuccessAt = Date()
                    return
                }
                lastFail = "parse-empty"
            } catch {
                if Task.isCancelled { return }
                lastFail = error.localizedDescription
            }
        }
        // Tüm endpoint'ler fail → eski limitleyi tutma (yanlış levha riski).
        guard !Task.isCancelled, !demoOverride else { return }
        lastError = lastFail ?? "OSM limit alınamadı"
        limitKmh = nil
        highway = nil
        roadName = nil
    }

    private static func parse(_ data: Data) -> (limit: Int?, highway: String?, name: String?)? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let elements = json["elements"] as? [[String: Any]], !elements.isEmpty
        else { return nil }

        var best: (score: Int, limit: Int?, highway: String?, name: String?)?

        for el in elements {
            guard let tags = el["tags"] as? [String: String] else { continue }
            let hw = tags["highway"] ?? ""
            let name = tags["name"] ?? tags["ref"]
            let limit = parseMaxspeed(tags["maxspeed"])
                ?? parseMaxspeed(tags["maxspeed:forward"])
                ?? defaultLimit(for: hw)
            let score = priority(highway: hw) + (limit != nil ? 10 : 0)
            if best == nil || score > best!.score {
                best = (score, limit, hw, name)
            }
        }
        guard let best else { return nil }
        return (best.limit, best.highway, best.name)
    }

    private static func parseMaxspeed(_ raw: String?) -> Int? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        s = s.lowercased()
        if s == "none" || s == "signals" { return nil }
        if s.contains("mph") { return nil }
        if s.contains("urban") || s.contains("tr:urban") { return 50 }
        if s.contains("rural") || s.contains("tr:rural") { return 90 }
        if s.contains("trunk") { return 110 }
        if s.contains("motorway") { return 120 }
        let digits = s.split(whereSeparator: { !$0.isNumber }).first.map(String.init)
        if let d = digits, let v = Int(d), v >= 20, v <= 160 { return v }
        return nil
    }

    private static func defaultLimit(for highway: String) -> Int? {
        switch highway {
        case "motorway", "motorway_link": return 120
        case "trunk", "trunk_link": return 110
        case "primary", "primary_link", "secondary", "secondary_link",
             "tertiary", "tertiary_link", "unclassified": return 90
        case "residential", "living_street": return 50
        default: return nil
        }
    }

    private static func priority(highway: String) -> Int {
        switch highway {
        case "motorway": return 5
        case "trunk": return 4
        case "primary": return 3
        case "secondary": return 2
        case "tertiary", "residential": return 1
        default: return 0
        }
    }
}
