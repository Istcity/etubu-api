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
        let road = EtubuRoadFix.shared
        let useLat = road.predictedCoordinate?.lat ?? lat
        let useLng = road.predictedCoordinate?.lng ?? lng
        let useSpeed = Int((road.speedKmh ?? Double(speedKmh)).rounded())
        // Tünel, altgeçit veya kırmızı ışıkta durma anında son geçerli levhayı 90 saniye boyunca koru
        guard useSpeed >= Self.movingKmhThreshold else {
            if let at = lastSuccessAt, Date().timeIntervalSince(at) < 90 { return }
            if limitKmh != nil || highway != nil || roadName != nil {
                clearLiveLimit()
            } else {
                task?.cancel()
                task = nil
            }
            return
        }
        guard let useLat, let useLng, useLat != 0, useLng != 0 else {
            // GPS sinyali anlık koptuğunda (tünel vb.) son levhayı 90 sn koru
            if let at = lastSuccessAt, Date().timeIntervalSince(at) < 90 { return }
            return
        }
        let coord = CLLocationCoordinate2D(latitude: useLat, longitude: useLng)

        if let last = lastSuccessCoord, let at = lastSuccessAt {
            let moved = CLLocation(latitude: last.latitude, longitude: last.longitude)
                .distance(from: CLLocation(latitude: useLat, longitude: useLng))
            let speedBandShifted = abs((limitKmh ?? 0) - useSpeed) > 45
            if moved < 35, Date().timeIntervalSince(at) < 18, !speedBandShifted { return }
        }
        if let at = lastAttemptAt, Date().timeIntervalSince(at) < 6 { return }

        lastAttemptAt = Date()
        task?.cancel()
        task = Task { await fetch(lat: useLat, lng: useLng, coord: coord, speedKmh: useSpeed) }
    }

    private func fetch(lat: Double, lng: Double, coord: CLLocationCoordinate2D, speedKmh: Int) async {
        guard !demoOverride else { return }
        let heading = EtubuRoadFix.shared.headingDeg ?? EtubuVehicleTelemetry.shared.headingDeg
        let q = """
        [out:json][timeout:12];
        way(around:35,\(lat),\(lng))["highway"]["highway"!~"footway|path|steps|cycleway|pedestrian|track|service|proposed|construction"];
        out tags geom 12;
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
                let imperial = Self.isUnitedStates(lat: lat, lng: lng)
                if let parsed = Self.parse(data, lat: lat, lng: lng, speedKmh: speedKmh, headingDeg: heading, imperial: imperial) {
                    guard !demoOverride else { return }
                    guard EtubuVehicleTelemetry.shared.kmh >= Self.movingKmhThreshold
                            || EtubuDemoDrive.isActive else { return }
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
        // Geçici fail: yakın zamanda doğru levha varsa tut (yanıp sönmesin).
        guard !Task.isCancelled, !demoOverride else { return }
        lastError = lastFail ?? "OSM limit alınamadı"
        if let at = lastSuccessAt, Date().timeIntervalSince(at) < 90,
           let last = lastSuccessCoord {
            let moved = CLLocation(latitude: last.latitude, longitude: last.longitude)
                .distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
            if moved < 300, limitKmh != nil { return }
        }
        limitKmh = nil
        highway = nil
        roadName = nil
    }

    /// Paralel yollar (otoyol vs. yan yol), yön açısı ve hız uyumunu değerlendiren hassas map-matching ayrıştırıcı.
    private static func parse(
        _ data: Data,
        lat: Double,
        lng: Double,
        speedKmh: Int,
        headingDeg: Double?,
        imperial: Bool
    ) -> (limit: Int?, highway: String?, name: String?)? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let elements = json["elements"] as? [[String: Any]], !elements.isEmpty
        else { return nil }

        var best: (score: Double, limit: Int?, highway: String?, name: String?)?

        for el in elements {
            guard let tags = el["tags"] as? [String: String] else { continue }
            let hw = tags["highway"] ?? ""
            let name = tags["name"] ?? tags["ref"]
            let isOneway = (tags["oneway"] == "yes" || tags["oneway"] == "1" || hw == "motorway")
            let limit = parseMaxspeed(tags["maxspeed"], imperial: imperial)
                ?? parseMaxspeed(tags["maxspeed:forward"], imperial: imperial)
                ?? defaultLimit(for: hw, imperial: imperial)

            // Geometri ve dik mesafe / yön hesaplama
            var minDistM: Double = 999.0
            var roadBearing: Double?

            if let geom = el["geometry"] as? [[String: Any]], geom.count >= 2 {
                for i in 0..<(geom.count - 1) {
                    guard
                        let lat1 = geom[i]["lat"] as? Double,
                        let lng1 = geom[i]["lon"] as? Double,
                        let lat2 = geom[i + 1]["lat"] as? Double,
                        let lng2 = geom[i + 1]["lon"] as? Double
                    else { continue }
                    let seg = distanceToSegmentM(lat: lat, lng: lng, lat1: lat1, lng1: lng1, lat2: lat2, lng2: lng2)
                    if seg.distM < minDistM {
                        minDistM = seg.distM
                        roadBearing = seg.bearingDeg
                    }
                }
            } else if let center = el["center"] as? [String: Double],
                      let cLat = center["lat"], let cLng = center["lon"] {
                minDistM = CLLocation(latitude: lat, longitude: lng)
                    .distance(from: CLLocation(latitude: cLat, longitude: cLng))
            }

            let score = roadScore(
                highway: hw,
                limit: limit,
                speedKmh: speedKmh,
                distM: minDistM,
                roadBearing: roadBearing,
                vehicleHeading: headingDeg,
                isOneway: isOneway
            )

            if best == nil || score > best!.score {
                best = (score, limit, hw, name)
            }
        }
        guard let best else { return nil }
        return (best.limit, best.highway, best.name)
    }

    /// Araç hızına, GPS segment mesafesine ve yön açısına göre doğru yolu seç.
    /// Otoyolda 110 km/s ile giderken yanındaki 50 km/s yan yol tamamen elenir.
    private static func roadScore(
        highway: String,
        limit: Int?,
        speedKmh: Int,
        distM: Double,
        roadBearing: Double?,
        vehicleHeading: Double?,
        isOneway: Bool
    ) -> Double {
        var s: Double = Double(priority(highway: highway) * 14)

        // 1. Dik mesafe puanı (yola yakınlık)
        s += max(0, 100.0 - (distM * 3.2))

        // 2. Yön / Açı eşleşmesi (Heading alignment)
        if let vHead = vehicleHeading, let rBear = roadBearing, vHead >= 0 {
            let diff1 = abs(vHead - rBear).truncatingRemainder(dividingBy: 360)
            let directAngle = min(diff1, 360 - diff1)
            let biAngle: Double
            if isOneway {
                biAngle = directAngle
            } else {
                let diff2 = abs(vHead - ((rBear + 180).truncatingRemainder(dividingBy: 360)))
                let oppAngle = min(diff2, 360 - diff2)
                biAngle = min(directAngle, oppAngle)
            }

            if biAngle <= 16 { s += 60 }
            else if biAngle <= 32 { s += 35 }
            else if biAngle <= 48 { s += 12 }
            else if biAngle >= 65 { s -= 85 } // Araca dik ya da ters açılı yolları filtrele
        }

        // 3. Hız tutarlılığı ve limit uyumu
        if let limit {
            s += 12
            let gap = abs(limit - speedKmh)
            if gap <= 15 { s += 45 }
            else if gap <= 30 { s += 24 }
            else if gap <= 50 { s += 10 }

            // Yüksek hızda giderken yan sokak / servis yolu limitini ağır cezalandır
            if speedKmh >= 85, limit <= 55 { s -= 130 }
            else if speedKmh >= 65, limit <= 45 { s -= 90 }
            else if speedKmh >= 110, limit <= 90 { s -= 35 }

            // Düşük hızda giderken otoyol ana gövdesi yerine yan yolu önceliklendir
            if speedKmh <= 30, limit >= 115 { s -= 80 }
            else if speedKmh <= 45, limit >= 120 { s -= 40 }
        }

        return s
    }

    /// Noktadan doğru parçasına dik mesafe (metre) ve doğru açısı (bearing)
    private static func distanceToSegmentM(
        lat: Double, lng: Double,
        lat1: Double, lng1: Double,
        lat2: Double, lng2: Double
    ) -> (distM: Double, bearingDeg: Double) {
        let earthR = 6_371_000.0
        let dLatRad = (lat2 - lat1) * .pi / 180.0
        let dLngRad = (lng2 - lng1) * .pi / 180.0
        let midLatRad = (lat1 + lat2) * 0.5 * .pi / 180.0
        let cosMid = cos(midLatRad)

        let x1 = 0.0, y1 = 0.0
        let x2 = (dLngRad * cosMid) * earthR
        let y2 = dLatRad * earthR

        let px = ((lng - lng1) * .pi / 180.0 * cosMid) * earthR
        let py = ((lat - lat1) * .pi / 180.0) * earthR

        let dx = x2 - x1
        let dy = y2 - y1
        let segLenSq = dx * dx + dy * dy

        var t = segLenSq > 0.001 ? (px * dx + py * dy) / segLenSq : 0.0
        t = max(0.0, min(1.0, t))

        let projX = x1 + t * dx
        let projY = y1 + t * dy

        let distM = hypot(px - projX, py - projY)

        let yB = sin(dLngRad) * cos(lat2 * .pi / 180.0)
        let xB = cos(lat1 * .pi / 180.0) * sin(lat2 * .pi / 180.0) - sin(lat1 * .pi / 180.0) * cos(lat2 * .pi / 180.0) * cos(dLngRad)
        var bearingDeg = atan2(yB, xB) * 180.0 / .pi
        if bearingDeg < 0 { bearingDeg += 360.0 }

        return (distM, bearingDeg)
    }

    private static func parseMaxspeed(_ raw: String?, imperial: Bool) -> Int? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        s = s.lowercased()
        if s == "none" || s == "signals" { return nil }
        if s.contains("urban") || s.contains("tr:urban") { return 50 }
        if s.contains("rural") || s.contains("tr:rural") { return 90 }
        if s.contains("trunk") { return imperial ? 89 : 110 }
        if s.contains("motorway") { return imperial ? 113 : 120 }
        let digits = s.split(whereSeparator: { !$0.isNumber }).first.map(String.init)
        guard let d = digits, let v = Int(d) else { return nil }
        if s.contains("mph") {
            guard v >= 5, v <= 90 else { return nil }
            return Int((Double(v) * 1.60934).rounded())
        }
        if imperial, v >= 5, v <= 85 {
            return Int((Double(v) * 1.60934).rounded())
        }
        if v >= 20, v <= 160 { return v }
        return nil
    }

    private static func defaultLimit(for highway: String, imperial: Bool) -> Int? {
        if imperial {
            switch highway {
            case "motorway", "motorway_link": return 113
            case "trunk", "trunk_link", "primary", "primary_link": return 89
            case "secondary", "secondary_link",
                 "tertiary", "tertiary_link", "unclassified": return 72
            case "residential": return 40
            case "living_street": return 24
            default: return nil
            }
        }
        switch highway {
        case "motorway", "motorway_link": return 120
        case "trunk", "trunk_link": return 110
        case "primary", "primary_link", "secondary", "secondary_link",
             "tertiary", "tertiary_link", "unclassified": return 90
        case "residential", "living_street": return 50
        default: return nil
        }
    }

    /// GPS in the United States (CONUS / Alaska / Hawaii).
    static func isUnitedStates(lat: Double, lng: Double) -> Bool {
        if lat >= 24.4, lat <= 49.4, lng >= -125.0, lng <= -66.2 { return true }
        if lat >= 51.0, lat <= 71.5, lng >= -170.0, lng <= -129.0 { return true }
        if lat >= 18.8, lat <= 22.4, lng >= -160.4, lng <= -154.7 { return true }
        return false
    }

    static func limitKmh(fromTag raw: String?, lat: Double, lng: Double) -> Int? {
        parseMaxspeed(raw, imperial: isUnitedStates(lat: lat, lng: lng))
    }

    private static func priority(highway: String) -> Int {
        switch highway {
        case "motorway": return 6
        case "trunk": return 5
        case "primary": return 4
        case "secondary": return 3
        case "tertiary": return 2
        case "residential": return 1
        default: return 0
        }
    }
}
