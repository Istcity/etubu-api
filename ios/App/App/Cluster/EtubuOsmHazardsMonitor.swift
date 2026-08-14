import Foundation
import CoreLocation
import Combine

/// Live OSM Overpass hazards around the vehicle (150 m / 60 s refresh).
/// OSM is the primary road-warning feed (EGM retired).
@MainActor
final class EtubuOsmHazardsMonitor: ObservableObject {
    static let shared = EtubuOsmHazardsMonitor()

    @Published private(set) var points: [EtubuRouteHazard] = []
    @Published private(set) var lastFetchFailed = false

    private var fetchCenter: CLLocationCoordinate2D?
    private var fetchedAt: Date?
    private var fetching = false

    private let fetchRadiusM = 900.0
    private let refetchDistM = 150.0
    private let refetchAge: TimeInterval = 60

    private let endpoints = [
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
    ]

    private init() {}

    /// Called from DriveWarnings while nav active (parked OK — fetch still runs).
    func tick(lat: Double?, lng: Double?, kmh: Int) {
        guard let lat, let lng, lat != 0, lng != 0 else { return }
        // Fetch regardless of speed so route-start has OSM mixed in immediately.
        refreshIfNeeded(lat: lat, lng: lng)
        _ = kmh
    }

    /// Rota planı sonrası paralel tetik — stale zorla.
    func prefetch(lat: Double, lng: Double) {
        guard lat != 0, lng != 0 else { return }
        fetchCenter = nil
        fetchedAt = nil
        refreshIfNeeded(lat: lat, lng: lng)
    }

    /// Filtered points for HUD (ahead + within warn×1.4).
    func ahead(
        lat: Double,
        lng: Double,
        heading: Double?,
        limit: Int = 8
    ) -> [(h: EtubuRouteHazard, dM: Double, stage: EtubuWarnStage)] {
        var scored: [(h: EtubuRouteHazard, dM: Double, stage: EtubuWarnStage)] = []
        for h in points {
            let dM = EtubuTrafikAPI.haversineKm(lat, lng, h.lat, h.lng) * 1000
            let t = EtubuHazardMerge.thresholds(for: h.kind)
            guard dM <= t.warn * 1.4 else { continue }
            if let heading, heading >= 0, dM > 40 {
                let b = Self.bearingDeg(lat, lng, h.lat, h.lng)
                if Self.angleDiff(b, heading) > 75 { continue }
            }
            let stage = EtubuHazardMerge.stage(for: h.kind, distM: dM)
            guard stage != .idle else { continue }
            scored.append((h, dM, stage))
        }
        scored.sort { $0.dM < $1.dM }
        return Array(scored.prefix(limit))
    }

    private func refreshIfNeeded(lat: Double, lng: Double) {
        if fetching { return }
        let stale: Bool = {
            guard let at = fetchedAt, let c = fetchCenter else { return true }
            if Date().timeIntervalSince(at) > refetchAge { return true }
            let moved = CLLocation(latitude: c.latitude, longitude: c.longitude)
                .distance(from: CLLocation(latitude: lat, longitude: lng))
            return moved >= refetchDistM
        }()
        guard stale else { return }
        fetching = true
        Task {
            let remote = await Self.fetchAround(lat: lat, lng: lng, endpoints: endpoints, radiusM: fetchRadiusM)
            await MainActor.run {
                self.fetching = false
                self.fetchCenter = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                self.fetchedAt = Date()
                self.lastFetchFailed = remote == nil
                if let remote {
                    self.points = remote
                }
                // On failure keep previous points; mark failed so mode can fall back to OSM-led.
            }
        }
    }

    private static func fetchAround(
        lat: Double,
        lng: Double,
        endpoints: [String],
        radiusM: Double
    ) async -> [EtubuRouteHazard]? {
        let r = Int(radiusM)
        let q = """
        [out:json][timeout:18];(
          node["highway"="speed_camera"](around:\(r),\(lat),\(lng));
          node["enforcement"="maxspeed"](around:\(r),\(lat),\(lng));
          node["enforcement"="average_speed"](around:\(r),\(lat),\(lng));
          node["camera:type"="section"](around:\(r),\(lat),\(lng));
          node["railway"="level_crossing"](around:\(r),\(lat),\(lng));
          node["railway"="crossing"](around:\(r),\(lat),\(lng));
          node["highway"="traffic_signals"](around:\(r),\(lat),\(lng));
          node["highway"="stop"](around:\(r),\(lat),\(lng));
          node["highway"="give_way"](around:\(r),\(lat),\(lng));
          node["highway"="crossing"](around:\(r),\(lat),\(lng));
          node["traffic_calming"="bump"](around:\(r),\(lat),\(lng));
          node["traffic_calming"="hump"](around:\(r),\(lat),\(lng));
          node["traffic_calming"="table"](around:\(r),\(lat),\(lng));
          node["amenity"="charging_station"](around:\(r),\(lat),\(lng));
          node["highway"="traffic_signals"]["crossing"="traffic_signals"](around:\(r),\(lat),\(lng));
          node["hazard"](around:\(r),\(lat),\(lng));
          node["mountain_pass"="yes"](around:\(r),\(lat),\(lng));
          node["natural"="saddle"](around:\(r),\(lat),\(lng));
          way["tunnel"="yes"](around:\(r),\(lat),\(lng));
          way["highway"="motorway"]["tunnel"="yes"](around:\(r),\(lat),\(lng));
          way["hazard"](around:\(r),\(lat),\(lng));
          way["mountain_pass"="yes"](around:\(r),\(lat),\(lng));
        );out body center;
        """
        for urlStr in endpoints {
            guard let url = URL(string: urlStr) else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
            req.httpBody = "data=\(q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q)".data(using: .utf8)
            req.timeoutInterval = 18
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { continue }
                return parse(data)
            } catch {
                continue
            }
        }
        return nil
    }

    private static func parse(_ data: Data) -> [EtubuRouteHazard] {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let elements = json["elements"] as? [[String: Any]]
        else { return [] }
        var out: [EtubuRouteHazard] = []
        for el in elements {
            let center = el["center"] as? [String: Any]
            let lat = (el["lat"] as? NSNumber)?.doubleValue ?? (el["lat"] as? Double)
                ?? (center?["lat"] as? NSNumber)?.doubleValue ?? (center?["lat"] as? Double)
            let lon = (el["lon"] as? NSNumber)?.doubleValue ?? (el["lon"] as? Double)
                ?? (center?["lon"] as? NSNumber)?.doubleValue ?? (center?["lon"] as? Double)
            guard let lat, let lon else { continue }
            let tags = el["tags"] as? [String: String] ?? [:]
            guard let kind = classify(tags) else { continue }
            let maxspeed = Int(tags["maxspeed"] ?? "")
            let oid: String = {
                if let i = el["id"] as? Int { return "\(i)" }
                if let n = el["id"] as? NSNumber { return n.stringValue }
                return "\(lat)-\(lon)"
            }()
            let lengthKm: Double? = kind == "corridor" ? 8 : nil
            let kw: Int? = kind == "charge" ? Int(tags["capacity"] ?? "") : nil
            out.append(EtubuRouteHazard(
                id: "osmhz-\(oid)",
                kind: kind,
                label: tags["name"] ?? tags["ref"] ?? Self.defaultLabel(kind),
                lat: lat,
                lng: lon,
                maxspeed: maxspeed,
                kw: kw,
                lengthKm: lengthKm
            ))
        }
        return EtubuHazardMerge.dedupePreferOfficial(out)
    }

    /// Shared OSM tag → hazard kind (live 900 m + along-route Overpass).
    nonisolated static func classify(_ tags: [String: String]) -> String? {
        if tags["amenity"] == "charging_station" { return "charge" }
        if tags["highway"] == "speed_camera"
            || tags["enforcement"] == "maxspeed"
            || tags["camera:type"] == "speed" {
            return "radar"
        }
        if tags["enforcement"] == "average_speed"
            || tags["camera:type"] == "section"
            || tags["traffic_sign"] == "average_speed" {
            return "corridor"
        }
        if tags["railway"] == "level_crossing"
            || tags["railway"] == "crossing"
            || tags["crossing:barrier"] != nil {
            return "railway"
        }
        if tags["tunnel"] == "yes" || tags["highway"] == "tunnel" {
            return "tunnel"
        }
        let hazard = (tags["hazard"] ?? "").lowercased()
        if ["curve", "curves", "winding_road", "bend"].contains(hazard) {
            return "winding"
        }
        if ["flood", "ice", "rock_fall", "falling_rocks", "landslide", "avalanche", "slippery"].contains(hazard) {
            return "road_condition"
        }
        if hazard == "animal_crossing" || tags["hazard"] == "animal" {
            return "animal"
        }
        if tags["mountain_pass"] == "yes" || tags["natural"] == "saddle" {
            return "climb"
        }
        if let inc = tags["incline"], inc.contains("%"),
           let n = Double(inc.replacingOccurrences(of: "%", with: "")), abs(n) >= 8 {
            return "climb"
        }
        if tags["highway"] == "traffic_signals" || tags["traffic_signals"] != nil {
            return "traffic_light"
        }
        if tags["highway"] == "stop" || tags["traffic_sign"] == "stop" {
            return "stop"
        }
        if tags["highway"] == "give_way"
            || tags["traffic_sign"] == "give_way"
            || tags["traffic_sign"] == "yield" {
            return "give_way"
        }
        if tags["highway"] == "crossing"
            || tags["crossing"] == "uncontrolled"
            || tags["crossing"] == "zebra"
            || tags["footway"] == "crossing" {
            return "crossing"
        }
        if let tc = tags["traffic_calming"], ["bump", "hump", "table"].contains(tc) {
            return "bump"
        }
        return nil
    }

    private static func defaultLabel(_ kind: String) -> String {
        EtubuRouteHazard.kindTitle(for: kind)
    }

    private static func bearingDeg(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let p1 = lat1 * .pi / 180
        let p2 = lat2 * .pi / 180
        let dl = (lon2 - lon1) * .pi / 180
        let y = sin(dl) * cos(p2)
        let x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)
        var deg = atan2(y, x) * 180 / .pi
        if deg < 0 { deg += 360 }
        return deg
    }

    private static func angleDiff(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return d > 180 ? 360 - d : d
    }
}
