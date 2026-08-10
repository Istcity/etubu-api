import Foundation
import CoreLocation
import Combine

/// Rota çizilmeden de çalışır: GPS çevresindeki OSM radar / hız koridoru + TR tohumları.
/// Web `RadarAlert` ile aynı yaklaşma / koridor girişi mantığı.
@MainActor
final class EtubuLiveRadarMonitor: ObservableObject {
    static let shared = EtubuLiveRadarMonitor()

    @Published private(set) var cameras: [EtubuRouteHazard] = []
    @Published private(set) var corridorActive = false
    @Published private(set) var corridorOver = false
    @Published private(set) var corridorAvgKmh: Int = 0
    @Published private(set) var corridorLimit: Int?
    @Published private(set) var corridorRemainLabel: String = ""
    @Published private(set) var corridorLabel: String = ""
    @Published private(set) var primary: EtubuWarnItem?

    private var fetchCenter: CLLocationCoordinate2D?
    private var fetchedAt: Date?
    private var fetching = false
    private var corridor: CorridorSession?
    private var lastEnterSpokenId = ""

    private let fetchRadiusM = 12_000.0
    private let refetchDistM = 4_500.0
    private let refetchAge: TimeInterval = 10 * 60
    private let aheadMaxM = 5_500.0
    private let headingTolerance = 55.0
    private let enterCorridorM = 280.0

    private let endpoints = [
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
    ]

    private struct CorridorSession {
        var id: String
        var enteredAt: Date
        var lastMs: Date
        var enterLat: Double
        var enterLng: Double
        var limit: Int
        var lengthM: Double
        var label: String
        var traveledM: Double
        var lastLat: Double
        var lastLng: Double
        var lostTicks: Int
    }

    private init() {
        cameras = EtubuRegion.lastKnownInTurkey ? Self.seedHazards() : []
        NotificationCenter.default.addObserver(
            forName: .etubuRegionDidChange,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let inTR = (note.object as? Bool) ?? EtubuRegion.lastKnownInTurkey
            Task { @MainActor in
                guard let self else { return }
                if inTR {
                    if self.cameras.isEmpty {
                        self.cameras = Self.seedHazards()
                    }
                }
            }
        }
    }

    /// DriveWarnings poll’undan çağrılır — rota olsun olmasın.
    func tick(lat: Double?, lng: Double?, heading: Double?, kmh: Int) {
        guard let lat, let lng, lat != 0, lng != 0 else { return }
        guard kmh >= EtubuOsmSpeedLimit.movingKmhThreshold else {
            if corridor == nil {
                primary = nil
                corridorActive = false
                corridorOver = false
            }
            return
        }

        refreshCamerasIfNeeded(lat: lat, lng: lng)

        let ahead = findAhead(lat: lat, lng: lng, heading: heading)
        let nearestCorridor = ahead.first { $0.h.kind == "corridor" }
        let corridorSnap = updateCorridor(
            lat: lat, lng: lng, kmh: kmh,
            nearest: nearestCorridor.map { (h: $0.h, dM: $0.dM) }
        )

        if let snap = corridorSnap {
            corridorActive = true
            corridorOver = snap.over
            corridorAvgKmh = snap.avg
            corridorLimit = snap.limit
            corridorRemainLabel = Self.fmtDist(snap.remainM)
            corridorLabel = snap.label
            primary = EtubuWarnItem(
                id: "live-corr-\(snap.id)",
                kind: "corridor",
                title: snap.over ? EtubuClusterL10n.slowDown : EtubuClusterL10n.radarCorridor,
                distanceLabel: Self.fmtDist(snap.remainM)
                    + (snap.limit > 0 ? " · \(snap.limit)" : "")
                    + (snap.avg > 0 ? " · \(snap.avg)" : ""),
                stage: snap.remainM < 400 ? .near : .mid,
                meta: snap.label
            )
            if snap.over {
                // YAVAŞLA uses true corridor measurement, not the blended display alone.
                let shown = snap.trueAvg > 0 ? snap.trueAvg : snap.avg
                primary = EtubuWarnItem(
                    id: "live-corr-over-\(snap.id)",
                    kind: "corridor",
                    title: EtubuClusterL10n.slowDown,
                    distanceLabel: "\(shown) / \(snap.limit)",
                    stage: .critical,
                    meta: snap.label
                )
            }
            return
        }

        corridorActive = false
        corridorOver = false
        corridorRemainLabel = ""
        corridorLabel = ""
        corridorLimit = nil
        corridorAvgKmh = 0

        guard let nearest = ahead.first else {
            primary = nil
            return
        }
        // Receding: if distance climbed vs last primary of same id, clear approaching UI.
        if let prev = primary, prev.id == nearest.h.id {
            let prevM = Self.parseDistM(prev.distanceLabel)
            if let prevM, nearest.dM > prevM + 35, nearest.dM > 180 {
                primary = nil
                return
            }
        }
        let stage: EtubuWarnStage
        if nearest.dM <= 300 { stage = .critical }
        else if nearest.dM <= 1000 { stage = .near }
        else if nearest.dM <= 2000 { stage = .mid }
        else { stage = .far }
        let lim = nearest.h.maxspeed.map { " · \($0)" } ?? ""
        let title = nearest.h.label.isEmpty ? nearest.h.kindTitle : nearest.h.label
        primary = EtubuWarnItem(
            id: nearest.h.id,
            kind: nearest.h.kind,
            title: title,
            distanceLabel: Self.fmtDist(nearest.dM) + lim,
            stage: stage,
            meta: nearest.h.maxspeed.map { "lim \($0)" } ?? ""
        )
    }

    private static func parseDistM(_ label: String) -> Double? {
        let head = label.components(separatedBy: "·").first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? label
        if head.contains("km") {
            let n = head.replacingOccurrences(of: "km", with: "")
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: ",", with: ".")
            if let v = Double(n) { return v * 1000 }
        }
        if head.contains("m") {
            let digits = head.filter { $0.isNumber }
            if let v = Double(digits) { return v }
        }
        return nil
    }

    private func refreshCamerasIfNeeded(lat: Double, lng: Double) {
        if fetching { return }
        let stale: Bool = {
            guard let at = fetchedAt, let c = fetchCenter else { return true }
            if Date().timeIntervalSince(at) > refetchAge { return true }
            let moved = CLLocation(latitude: c.latitude, longitude: c.longitude)
                .distance(from: CLLocation(latitude: lat, longitude: lng))
            return moved > refetchDistM
        }()
        guard stale else { return }
        fetching = true
        Task {
            let remote = await Self.fetchOverpass(lat: lat, lng: lng, endpoints: endpoints, radiusM: fetchRadiusM)
            await MainActor.run {
                self.fetching = false
                self.fetchCenter = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                self.fetchedAt = Date()
                self.cameras = Self.merge(
                    seeds: EtubuRegion.lastKnownInTurkey ? Self.seedHazards() : [],
                    remote: remote
                )
            }
        }
    }

    private func findAhead(lat: Double, lng: Double, heading: Double?) -> [(h: EtubuRouteHazard, dM: Double)] {
        var ahead: [(h: EtubuRouteHazard, dM: Double)] = []
        for h in cameras {
            let dM = EtubuTrafikAPI.haversineKm(lat, lng, h.lat, h.lng) * 1000
            guard dM <= aheadMaxM else { continue }
            if let heading, heading >= 0 {
                let b = Self.bearingDeg(lat, lng, h.lat, h.lng)
                let diff = Self.angleDiff(b, heading)
                if diff > headingTolerance {
                    if dM < 180, diff > 120 { continue }
                    continue
                }
            }
            ahead.append((h, dM))
        }
        ahead.sort { $0.dM < $1.dM }
        return ahead
    }

    private struct CorridorSnap {
        var id: String
        var remainM: Double
        var limit: Int
        /// Blended display avg (instant→historical along corridor progress).
        var avg: Int
        /// True distance/time corridor measurement — used for YAVAŞLA / over, not the blend alone.
        var trueAvg: Int
        var over: Bool
        var label: String
        var entered: Bool
    }

    private func updateCorridor(
        lat: Double, lng: Double, kmh: Int,
        nearest: (h: EtubuRouteHazard, dM: Double)?
    ) -> CorridorSnap? {
        if var state = corridor {
            tickTravel(&state, lat: lat, lng: lng, kmh: kmh)
            let traveled = state.traveledM
            let remain = max(0, state.lengthM - traveled)
            let dToStart = EtubuTrafikAPI.haversineKm(lat, lng, state.enterLat, state.enterLng) * 1000
            let sameAhead = nearest?.h.id == state.id
            state.lostTicks = sameAhead ? 0 : state.lostTicks + 1
            let pastEnd = traveled >= state.lengthM - 60 || dToStart > state.lengthM + 350
            let lostTrack = state.lostTicks >= 6 && (nearest == nil || (nearest?.dM ?? 0) > 700) && dToStart > 450
            if remain < 60 || pastEnd || lostTrack {
                corridor = nil
                return nil
            }
            corridor = state
            let (display, trueAvg) = corridorAvgs(state, kmh: kmh)
            return CorridorSnap(
                id: state.id,
                remainM: remain,
                limit: state.limit,
                avg: display,
                trueAvg: trueAvg,
                over: trueAvg > 0 && trueAvg > state.limit + 2,
                label: state.label,
                entered: false
            )
        }

        guard let nearest, nearest.h.kind == "corridor", nearest.dM < enterCorridorM else {
            return nil
        }
        let lengthM = (nearest.h.lengthKm ?? 10) * 1000
        let lim = nearest.h.maxspeed ?? 120
        let label = nearest.h.label.isEmpty ? EtubuClusterL10n.t("warnKindCorridor") : nearest.h.label
        corridor = CorridorSession(
            id: nearest.h.id,
            enteredAt: Date(),
            lastMs: Date(),
            enterLat: lat,
            enterLng: lng,
            limit: lim,
            lengthM: lengthM,
            label: label,
            traveledM: 0,
            lastLat: lat,
            lastLng: lng,
            lostTicks: 0
        )
        if lastEnterSpokenId != nearest.h.id {
            lastEnterSpokenId = nearest.h.id
            // TTS klipleri TR — UI dili bağımsız
            EtubuClusterAudioBridge.playWarnCue(
                id: "enter-\(nearest.h.id)",
                kind: "corridor",
                stage: "near",
                phrase: lim > 0 ? "Koridor giriş. Hız sınır \(lim)" : "Koridor giriş"
            )
        }
        // Entry: show vehicle speed immediately (no blank / 0 waiting for 35 m).
        let entryAvg = max(0, min(220, kmh))
        return CorridorSnap(
            id: nearest.h.id,
            remainM: lengthM,
            limit: lim,
            avg: entryAvg,
            trueAvg: 0,
            over: false,
            label: label,
            entered: true
        )
    }

    private func tickTravel(_ state: inout CorridorSession, lat: Double, lng: Double, kmh: Int) {
        let now = Date()
        let dt = min(2.5, max(0, now.timeIntervalSince(state.lastMs)))
        state.lastMs = now
        guard dt > 0.05, dt < 2.2 else {
            state.lastLat = lat
            state.lastLng = lng
            return
        }
        // Prefer vehicle speed×dt so corridor avg stays consistent with dial; GPS corrects.
        var addM = kmh >= 2 ? (Double(kmh) / 3.6) * dt : 0
        let step = EtubuTrafikAPI.haversineKm(state.lastLat, state.lastLng, lat, lng) * 1000
        let implied = dt > 0 ? (step / dt) * 3.6 : 0
        if step > 0.4, step < 120, implied <= 260, kmh < 2 || abs(implied - Double(kmh)) <= 55 {
            addM = addM > 0 ? addM * 0.7 + step * 0.3 : step
        }
        if addM > 0 { state.traveledM += addM }
        state.lastLat = lat
        state.lastLng = lng
    }

    /// Display blend + true corridor average (camera measurement).
    /// - Entry / thin samples: display = vehicle speed
    /// - Progress 0→1: hist weight 50%→90%, instant 50%→10%
    /// - `trueAvg` is distance/time only (for YAVAŞLA); 0 until ≥35 m & ~4.3 s
    private func corridorAvgs(_ state: CorridorSession, kmh: Int) -> (display: Int, trueAvg: Int) {
        let instant = Double(max(0, min(220, kmh)))
        let traveled = state.traveledM
        let elapsedH = Date().timeIntervalSince(state.enteredAt) / 3600
        let trueRaw: Double? = {
            guard traveled >= 35, elapsedH >= 0.0012 else { return nil }
            let avg = traveled / 1000 / elapsedH
            guard avg.isFinite, avg >= 0 else { return nil }
            return min(220, avg)
        }()
        let trueAvg = trueRaw.map { Int($0.rounded()) } ?? 0
        guard let hist = trueRaw else {
            return (Int(instant.rounded()), 0)
        }
        let progress = state.lengthM > 0
            ? min(1, max(0, traveled / state.lengthM))
            : 0
        // Start ~50% historical + 50% instant → end ~90% / 10%.
        let histW = 0.5 + 0.4 * progress
        let blended = histW * hist + (1 - histW) * instant
        let display = min(220, max(0, Int(blended.rounded())))
        return (display, trueAvg)
    }

    // MARK: - Fetch / seeds

    private static func seedHazards() -> [EtubuRouteHazard] {
        [
            .init(id: "tem-gebze", kind: "radar", label: "Gebze TEM", lat: 40.802, lng: 29.438, maxspeed: 120),
            .init(id: "tem-izmit", kind: "radar", label: "İzmit TEM", lat: 40.765, lng: 29.94, maxspeed: 120),
            .init(id: "kor-sakarya", kind: "corridor", label: "Sakarya koridor", lat: 40.74, lng: 30.35, maxspeed: 120, lengthKm: 12),
            .init(id: "kor-ankara-bati", kind: "corridor", label: "Ankara batı koridor", lat: 39.95, lng: 32.45, maxspeed: 120, lengthKm: 18),
            .init(id: "o5-kemalpasa", kind: "radar", label: "Kemalpaşa O-5", lat: 38.45, lng: 27.45, maxspeed: 130),
            .init(id: "kor-o5-balikesir", kind: "corridor", label: "Balıkesir O-5 koridor", lat: 39.55, lng: 27.95, maxspeed: 130, lengthKm: 22),
            .init(id: "kor-o5-manisa", kind: "corridor", label: "Manisa O-5 koridor", lat: 38.72, lng: 27.35, maxspeed: 130, lengthKm: 15),
            .init(id: "kor-konya", kind: "corridor", label: "Konya koridor", lat: 38.0, lng: 32.55, maxspeed: 110, lengthKm: 16),
            .init(id: "fixed-aksaray", kind: "radar", label: "Aksaray", lat: 38.37, lng: 34.03, maxspeed: 110),
            .init(id: "fixed-hadimkoy", kind: "radar", label: "Hadımköy", lat: 41.14, lng: 28.6, maxspeed: 120),
            .init(id: "kor-catalca", kind: "corridor", label: "Çatalca koridor", lat: 41.15, lng: 28.35, maxspeed: 120, lengthKm: 14),
            .init(id: "fixed-silivri", kind: "radar", label: "Silivri", lat: 41.08, lng: 28.25, maxspeed: 120),
            .init(id: "fixed-aydin", kind: "radar", label: "Aydın O-31", lat: 37.84, lng: 27.84, maxspeed: 120),
            .init(id: "kor-antalya", kind: "corridor", label: "Antalya koridor", lat: 37.05, lng: 30.65, maxspeed: 110, lengthKm: 10),
        ]
    }

    private static func merge(seeds: [EtubuRouteHazard], remote: [EtubuRouteHazard]) -> [EtubuRouteHazard] {
        var map: [String: EtubuRouteHazard] = [:]
        for h in seeds + remote {
            let key = h.id.isEmpty
                ? "\(h.kind)-\(Int(h.lat * 1000))-\(Int(h.lng * 1000))"
                : h.id
            if map[key] == nil { map[key] = h }
        }
        return Array(map.values)
    }

    private static func fetchOverpass(
        lat: Double, lng: Double,
        endpoints: [String],
        radiusM: Double
    ) async -> [EtubuRouteHazard] {
        let q = """
        [out:json][timeout:15];(
          node["highway"="speed_camera"](around:\(Int(radiusM)),\(lat),\(lng));
          node["enforcement"="maxspeed"](around:\(Int(radiusM)),\(lat),\(lng));
          node["enforcement"="average_speed"](around:\(Int(radiusM)),\(lat),\(lng));
          node["camera:type"="section"](around:\(Int(radiusM)),\(lat),\(lng));
        );out body;
        """
        for urlStr in endpoints {
            guard let url = URL(string: urlStr) else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
            req.httpBody = "data=\(q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q)".data(using: .utf8)
            req.timeoutInterval = 16
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { continue }
                return parseOverpass(data)
            } catch {
                continue
            }
        }
        return []
    }

    private static func parseOverpass(_ data: Data) -> [EtubuRouteHazard] {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let elements = json["elements"] as? [[String: Any]]
        else { return [] }
        var out: [EtubuRouteHazard] = []
        for el in elements {
            let lat = (el["lat"] as? NSNumber)?.doubleValue ?? (el["lat"] as? Double)
            let lon = (el["lon"] as? NSNumber)?.doubleValue ?? (el["lon"] as? Double)
            guard let lat, let lon else { continue }
            let tags = el["tags"] as? [String: String] ?? [:]
            let isCorridor = tags["enforcement"] == "average_speed"
                || tags["camera:type"] == "section"
                || tags["traffic_sign"] == "average_speed"
            let maxspeed = Int(tags["maxspeed"] ?? "")
            let lengthKm: Double? = {
                if let raw = tags["length"], let v = Double(raw) { return v }
                return isCorridor ? 8 : nil
            }()
            let oid: String = {
                if let i = el["id"] as? Int { return "\(i)" }
                if let n = el["id"] as? NSNumber { return n.stringValue }
                return "\(lat)-\(lon)"
            }()
            out.append(EtubuRouteHazard(
                id: "osm-\(oid)",
                kind: isCorridor ? "corridor" : "radar",
                label: tags["name"] ?? tags["ref"] ?? "",
                lat: lat,
                lng: lon,
                maxspeed: maxspeed,
                lengthKm: lengthKm
            ))
        }
        return out
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

    private static func fmtDist(_ m: Double) -> String {
        guard m.isFinite, m >= 0 else { return "" }
        if m >= 1000 {
            let km = m / 1000
            return km >= 10 ? String(format: "%.0f km", km) : String(format: "%.1f km", km)
        }
        if m >= 100 { return "\(Int((m / 50).rounded() * 50)) m" }
        return "\(Int((m / 10).rounded() * 10)) m"
    }
}
