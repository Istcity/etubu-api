import Foundation
import CoreLocation

/// Küresel ve ulusal hız koridorları — 30 günlük (aylık) arka plan önbellek.
/// Kaynak sırası: gömülü EGM+OSM JSON → disk cache → ayda bir arka plan Overpass yenileme.
/// Rota başına sunucuya sürekli canlı sorgu atılmaz; sabit noktalar ayda bir arka planda yenilenip diske yazılır.
enum EtubuTrCorridorStore {
    private static let cacheName = "etubu-global-corridors-v4.json"
    private static let bundleResource = "etubu-tr-corridors"
    private static let fetchedAtKey = "etubu.global.corridors.fetchedAt"
    /// 30 günlük (aylık) önbellek süresi — her açılışta canlı çekmek yerine ayda 1 kez yenilenir.
    private static let monthInterval: TimeInterval = 30 * 24 * 3600
    private static let endpoints = [
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
        "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
    ]

    private static let lock = NSLock()
    private static var memory: [EtubuRouteHazard] = []
    private static var loadedDisk = false
    private static var fetching = false

    /// Küresel olarak aktiftir.
    static var isEnabled: Bool { true }

    static func refreshIfNeeded(force: Bool = false) {
        loadDiskIfNeeded()
        let last = UserDefaults.standard.double(forKey: fetchedAtKey)
        let age = Date().timeIntervalSince1970 - last
        if !force, last > 0, age < monthInterval, memory.count >= 20 { return }
        guard !fetching else { return }
        fetching = true
        Task.detached(priority: .background) {
            let remote = await fetchAllTiles()
            await MainActor.run {
                lock.lock()
                defer { lock.unlock() }
                fetching = false
                if !remote.isEmpty {
                    // Keep seed & verified official pins; Overpass fills gaps.
                    let keep = memory.filter {
                        $0.id.hasPrefix("egm-") || $0.id.contains("-seed-")
                    }
                    memory = Self.dedupe(keep + remote + memory)
                    persist(memory)
                    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: fetchedAtKey)
                }
            }
        }
    }

    /// Optional bonus when createRoute succeeds — never required for corridors.
    static func ingestOfficial(_ corridors: [EtubuRouteHazard]) {
        guard isEnabled, !corridors.isEmpty else { return }
        loadDiskIfNeeded()
        lock.lock()
        defer { lock.unlock() }
        let onlyCor = corridors.filter { $0.kind == "corridor" }
        guard !onlyCor.isEmpty else { return }
        memory = dedupe(onlyCor + memory)
        persist(memory)
    }

    static func nearby(lat: Double, lng: Double, radiusKm: Double = 80) -> [EtubuRouteHazard] {
        let all = snapshot()
        return all.filter { h in
            distanceToCorridorKm(lat: lat, lng: lng, h: h) <= radiusKm
        }
    }

    static func alongRoute(
        coords: [(lat: Double, lng: Double)],
        maxOffM: Double = 3500
    ) -> [EtubuRouteHazard] {
        guard coords.count >= 2 else { return [] }
        var out: [EtubuRouteHazard] = []
        for h in snapshot() {
            let near = nearestRouteToCorridor(coords: coords, h: h)
            guard near.dM <= maxOffM else { continue }
            var pinned = h
            pinned.routeIdx = near.idx
            pinned.alongKm = EtubuTrafikAPI.alongKm(coords: coords, upTo: near.idx)
            out.append(pinned)
        }
        return out
    }

    static func snapshot() -> [EtubuRouteHazard] {
        loadDiskIfNeeded()
        lock.lock()
        defer { lock.unlock() }
        return memory.isEmpty ? fallbackSeeds : memory
    }

    /// Haversine distance (km) to corridor start, end, or segment midpoint.
    static func distanceToCorridorKm(lat: Double, lng: Double, h: EtubuRouteHazard) -> Double {
        var best = EtubuTrafikAPI.haversineKm(lat, lng, h.lat, h.lng)
        if let elat = h.endLat, let elng = h.endLng {
            best = min(best, EtubuTrafikAPI.haversineKm(lat, lng, elat, elng))
            let midLat = (h.lat + elat) * 0.5
            let midLng = (h.lng + elng) * 0.5
            best = min(best, EtubuTrafikAPI.haversineKm(lat, lng, midLat, midLng))
        }
        return best
    }

    // MARK: - Bundle / disk

    private static let fallbackSeeds: [EtubuRouteHazard] = [
        .init(id: "osm-trcor-seed-0", kind: "corridor", label: "Sakarya TEM koridor", lat: 40.74, lng: 30.35, maxspeed: 120, lengthKm: 12),
        .init(id: "osm-trcor-seed-1", kind: "corridor", label: "Ankara batı koridor", lat: 39.95, lng: 32.45, maxspeed: 120, lengthKm: 18),
        .init(id: "osm-trcor-seed-2", kind: "corridor", label: "Balıkesir O-5 koridor", lat: 39.55, lng: 27.95, maxspeed: 130, lengthKm: 22),
        .init(id: "osm-trcor-seed-3", kind: "corridor", label: "Manisa O-5 koridor", lat: 38.72, lng: 27.35, maxspeed: 130, lengthKm: 15),
        .init(id: "osm-trcor-seed-4", kind: "corridor", label: "Konya koridor", lat: 38.0, lng: 32.55, maxspeed: 110, lengthKm: 16),
        .init(id: "osm-trcor-seed-5", kind: "corridor", label: "Çatalca koridor", lat: 41.15, lng: 28.35, maxspeed: 120, lengthKm: 14),
        .init(id: "osm-trcor-seed-6", kind: "corridor", label: "Antalya koridor", lat: 37.05, lng: 30.65, maxspeed: 110, lengthKm: 10),
        .init(id: "osm-trcor-seed-7", kind: "corridor", label: "Kınalı Kuzey Marmara", lat: 41.18, lng: 28.15, maxspeed: 120, lengthKm: 16),
        .init(id: "osm-trcor-seed-8", kind: "corridor", label: "İzmit Kuzey Marmara", lat: 40.82, lng: 29.92, maxspeed: 120, lengthKm: 18),
        .init(id: "osm-trcor-seed-9", kind: "corridor", label: "Bolu TEM koridor", lat: 40.73, lng: 31.61, maxspeed: 120, lengthKm: 14),
    ]

    private static func nearestRouteToCorridor(
        coords: [(lat: Double, lng: Double)],
        h: EtubuRouteHazard
    ) -> (dM: Double, idx: Int) {
        let a = EtubuTrafikAPI.nearestRouteIndex(coords: coords, lat: h.lat, lng: h.lng)
        guard let elat = h.endLat, let elng = h.endLng else { return a }
        let b = EtubuTrafikAPI.nearestRouteIndex(coords: coords, lat: elat, lng: elng)
        let mid = EtubuTrafikAPI.nearestRouteIndex(
            coords: coords,
            lat: (h.lat + elat) * 0.5,
            lng: (h.lng + elng) * 0.5
        )
        return [a, b, mid].min(by: { $0.dM < $1.dM }) ?? a
    }

    private static func loadDiskIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        if loadedDisk { return }
        loadedDisk = true

        if let dir = cacheURL() {
            let url = dir.appendingPathComponent(cacheName)
            if let rows = decodeRows(from: url), !rows.isEmpty {
                memory = rows
                return
            }
        }
        if let bundled = loadBundledRows(), !bundled.isEmpty {
            memory = bundled
            persist(memory)
            return
        }
        memory = fallbackSeeds
    }

    private static func loadBundledRows() -> [EtubuRouteHazard]? {
        guard let url = Bundle.main.url(forResource: bundleResource, withExtension: "json") else {
            return nil
        }
        return decodeRows(from: url)
    }

    private static func decodeRows(from url: URL) -> [EtubuRouteHazard]? {
        guard let data = try? Data(contentsOf: url),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return nil }
        return rows.compactMap(hazard(from:))
    }

    private static func hazard(from row: [String: Any]) -> EtubuRouteHazard? {
        let lat = (row["lat"] as? NSNumber)?.doubleValue ?? (row["lat"] as? Double)
        let lng = (row["lng"] as? NSNumber)?.doubleValue ?? (row["lng"] as? Double)
        guard let lat, let lng else { return nil }
        let id = (row["id"] as? String) ?? "osm-trcor-\(lat)-\(lng)"
        let maxspeed: Int? = {
            if let i = row["maxspeed"] as? Int, i > 0 { return i }
            if let n = row["maxspeed"] as? NSNumber, n.intValue > 0 { return n.intValue }
            return nil
        }()
        let lengthKm: Double? = {
            if let d = row["lengthKm"] as? Double { return d }
            if let n = row["lengthKm"] as? NSNumber { return n.doubleValue }
            return nil
        }()
        let endLat = (row["endLat"] as? NSNumber)?.doubleValue ?? (row["endLat"] as? Double)
        let endLng = (row["endLng"] as? NSNumber)?.doubleValue ?? (row["endLng"] as? Double)
        return EtubuRouteHazard(
            id: id,
            kind: "corridor",
            label: (row["label"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? EtubuClusterL10n.t("warnKindCorridor"),
            lat: lat,
            lng: lng,
            maxspeed: maxspeed,
            lengthKm: lengthKm,
            endLat: endLat,
            endLng: endLng
        )
    }

    // MARK: - Weekly OSM (Turkey tiles)

    private static let tiles: [(s: Double, w: Double, n: Double, e: Double)] = [
        (39.8, 26.0, 42.3, 30.6),
        (36.5, 26.0, 39.9, 30.2),
        (36.0, 27.5, 38.2, 36.6),
        (37.4, 30.0, 41.1, 35.8),
        (40.4, 31.0, 42.3, 42.1),
        (36.0, 35.8, 38.6, 42.2),
        (37.0, 38.0, 42.1, 44.8),
    ]

    private static func fetchAllTiles() async -> [EtubuRouteHazard] {
        var all: [EtubuRouteHazard] = []
        var queryTiles = tiles

        // Kullanıcının mevcut coğrafi konumu etrafındaki dinamik bölge kutusu (Küresel destek)
        let lat = EtubuVehicleTelemetry.shared.latitude
        let lng = EtubuVehicleTelemetry.shared.longitude
        if let lat, let lng, lat != 0, lng != 0 {
            let span = 1.4
            let userTile = (s: max(-85, lat - span), w: max(-180, lng - span), n: min(85, lat + span), e: min(180, lng + span))
            queryTiles.insert(userTile, at: 0)
        }

        for tile in queryTiles {
            let batch = await fetchTile(tile)
            all.append(contentsOf: batch)
            try? await Task.sleep(nanoseconds: 450_000_000)
        }
        return dedupe(all)
    }

    private static func fetchTile(_ b: (s: Double, w: Double, n: Double, e: Double)) async -> [EtubuRouteHazard] {
        let q = """
        [out:json][timeout:55];(
          node["enforcement"="average_speed"](\(b.s),\(b.w),\(b.n),\(b.e));
          node["camera:type"="section"](\(b.s),\(b.w),\(b.n),\(b.e));
          node["traffic_sign"="average_speed"](\(b.s),\(b.w),\(b.n),\(b.e));
          way["enforcement"="average_speed"](\(b.s),\(b.w),\(b.n),\(b.e));
          relation["type"="enforcement"]["enforcement"="average_speed"](\(b.s),\(b.w),\(b.n),\(b.e));
        );out center tags;
        """
        for urlStr in endpoints {
            guard let url = URL(string: urlStr) else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
            req.setValue("Etubu/1.0 (com.etubu.app)", forHTTPHeaderField: "User-Agent")
            req.httpBody = "data=\(q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q)".data(using: .utf8)
            req.timeoutInterval = 58
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { continue }
                let parsed = parse(data)
                if !parsed.isEmpty { return parsed }
            } catch {
                continue
            }
        }
        return []
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
            guard let lat, let lon, EtubuRegion.inTurkeyBounds(lat: lat, lng: lon) else { continue }
            let tags = el["tags"] as? [String: String] ?? [:]
            let typ = (el["type"] as? String) ?? "n"
            let oid: String = {
                if let i = el["id"] as? Int { return "\(typ)-\(i)" }
                if let n = el["id"] as? NSNumber { return "\(typ)-\(n.stringValue)" }
                return "\(typ)-\(lat)-\(lon)"
            }()
            let maxspeed = Int(tags["maxspeed"] ?? "")
            let lengthKm: Double = {
                if let raw = tags["length"], let m = Double(raw.replacingOccurrences(of: " km", with: "")) {
                    return m > 80 ? m / 1000 : m
                }
                return 8
            }()
            out.append(EtubuRouteHazard(
                id: "osm-trcor-\(oid)",
                kind: "corridor",
                label: tags["name"] ?? tags["ref"] ?? EtubuClusterL10n.t("warnKindCorridor"),
                lat: lat,
                lng: lon,
                maxspeed: maxspeed,
                lengthKm: lengthKm
            ))
        }
        return out
    }

    private static func dedupe(_ list: [EtubuRouteHazard]) -> [EtubuRouteHazard] {
        // Prefer EGM over OSM/seed when close.
        let ranked = list.sorted { a, b in
            rank(a.id) < rank(b.id)
        }
        return EtubuHazardMerge.dedupePreferOfficial(ranked, dedupeM: 120)
    }

    private static func rank(_ id: String) -> Int {
        if id.hasPrefix("egm-") { return 0 }
        if id.contains("-seed-") { return 2 }
        return 1
    }

    private static func cacheURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Etubu", isDirectory: true)
    }

    private static func persist(_ list: [EtubuRouteHazard]) {
        guard let dir = cacheURL() else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let rows: [[String: Any]] = list.map { h in
            var row: [String: Any] = [
                "id": h.id,
                "label": h.label,
                "lat": h.lat,
                "lng": h.lng,
                "maxspeed": h.maxspeed ?? 0,
                "lengthKm": h.lengthKm ?? 8,
            ]
            if let elat = h.endLat { row["endLat"] = elat }
            if let elng = h.endLng { row["endLng"] = elng }
            return row
        }
        guard let data = try? JSONSerialization.data(withJSONObject: rows) else { return }
        try? data.write(to: dir.appendingPathComponent(cacheName), options: .atomic)
    }
}
