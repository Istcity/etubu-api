import Foundation
import CoreLocation

/// Türkiye hız koridorları: uygulama içi tohum + OSM’den haftalık yenileme.
/// Yalnız dil TR iken HUD / rota havuzuna karışır. EGM kullanılmaz.
enum EtubuTrCorridorStore {
    private static let cacheName = "etubu-tr-corridors-v1.json"
    private static let fetchedAtKey = "etubu.tr.corridors.fetchedAt"
    private static let week: TimeInterval = 7 * 24 * 3600
    private static let endpoints = [
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
    ]

    private static let lock = NSLock()
    private static var memory: [EtubuRouteHazard] = []
    private static var loadedDisk = false
    private static var fetching = false

    /// Dil TR değilse boş.
    static var isEnabled: Bool { EtubuAppLanguage.current == .tr }

    static func refreshIfNeeded() {
        guard isEnabled else { return }
        loadDiskIfNeeded()
        let last = UserDefaults.standard.double(forKey: fetchedAtKey)
        let age = Date().timeIntervalSince1970 - last
        if last > 0, age < week, !memory.isEmpty { return }
        guard !fetching else { return }
        fetching = true
        Task.detached(priority: .utility) {
            let remote = await fetchAllTiles()
            await MainActor.run {
                lock.lock()
                defer { lock.unlock() }
                fetching = false
                if !remote.isEmpty {
                    memory = Self.dedupe(bundled + remote)
                    persist(memory)
                    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: fetchedAtKey)
                } else if memory.isEmpty {
                    memory = bundled
                }
            }
        }
    }

    static func nearby(lat: Double, lng: Double, radiusKm: Double = 80) -> [EtubuRouteHazard] {
        guard isEnabled else { return [] }
        let all = snapshot()
        return all.filter {
            EtubuTrafikAPI.haversineKm(lat, lng, $0.lat, $0.lng) <= radiusKm
        }
    }

    static func alongRoute(
        coords: [(lat: Double, lng: Double)],
        maxOffM: Double = 3500
    ) -> [EtubuRouteHazard] {
        guard isEnabled, coords.count >= 2 else { return [] }
        var out: [EtubuRouteHazard] = []
        for h in snapshot() {
            let near = EtubuTrafikAPI.nearestRouteIndex(coords: coords, lat: h.lat, lng: h.lng)
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
        return memory.isEmpty ? bundled : memory
    }

    // MARK: - Bundled TR seeds (offline)

    private static let bundled: [EtubuRouteHazard] = [
        .init(id: "osm-trcor-sakarya", kind: "corridor", label: "Sakarya TEM koridor", lat: 40.74, lng: 30.35, maxspeed: 120, lengthKm: 12),
        .init(id: "osm-trcor-ankara-bati", kind: "corridor", label: "Ankara batı koridor", lat: 39.95, lng: 32.45, maxspeed: 120, lengthKm: 18),
        .init(id: "osm-trcor-o5-balikesir", kind: "corridor", label: "Balıkesir O-5 koridor", lat: 39.55, lng: 27.95, maxspeed: 130, lengthKm: 22),
        .init(id: "osm-trcor-o5-manisa", kind: "corridor", label: "Manisa O-5 koridor", lat: 38.72, lng: 27.35, maxspeed: 130, lengthKm: 15),
        .init(id: "osm-trcor-konya", kind: "corridor", label: "Konya koridor", lat: 38.0, lng: 32.55, maxspeed: 110, lengthKm: 16),
        .init(id: "osm-trcor-catalca", kind: "corridor", label: "Çatalca koridor", lat: 41.15, lng: 28.35, maxspeed: 120, lengthKm: 14),
        .init(id: "osm-trcor-antalya", kind: "corridor", label: "Antalya koridor", lat: 37.05, lng: 30.65, maxspeed: 110, lengthKm: 10),
        .init(id: "osm-trcor-o7-kinali", kind: "corridor", label: "Kınalı Kuzey Marmara", lat: 41.18, lng: 28.15, maxspeed: 120, lengthKm: 16),
        .init(id: "osm-trcor-o7-izmit", kind: "corridor", label: "İzmit Kuzey Marmara", lat: 40.82, lng: 29.92, maxspeed: 120, lengthKm: 18),
        .init(id: "osm-trcor-o4-bolu", kind: "corridor", label: "Bolu TEM koridor", lat: 40.73, lng: 31.61, maxspeed: 120, lengthKm: 14),
        .init(id: "osm-trcor-o21-aksaray", kind: "corridor", label: "Aksaray O-21 koridor", lat: 38.37, lng: 34.03, maxspeed: 110, lengthKm: 16),
        .init(id: "osm-trcor-o31-aydin", kind: "corridor", label: "Aydın O-31 koridor", lat: 37.84, lng: 27.84, maxspeed: 120, lengthKm: 12),
        .init(id: "osm-trcor-o22-bursa", kind: "corridor", label: "Bursa O-22 koridor", lat: 40.22, lng: 29.06, maxspeed: 120, lengthKm: 12),
        .init(id: "osm-trcor-o51-adana", kind: "corridor", label: "Adana O-51 koridor", lat: 37.02, lng: 35.32, maxspeed: 120, lengthKm: 14),
        .init(id: "osm-trcor-o52-gaziantep", kind: "corridor", label: "Gaziantep O-52 koridor", lat: 37.07, lng: 37.38, maxspeed: 120, lengthKm: 14),
        .init(id: "osm-trcor-o20-ankara", kind: "corridor", label: "Ankara O-20 koridor", lat: 39.97, lng: 32.85, maxspeed: 100, lengthKm: 10),
        .init(id: "osm-trcor-o30-izmir", kind: "corridor", label: "İzmir çevre koridor", lat: 38.42, lng: 27.18, maxspeed: 100, lengthKm: 10),
        .init(id: "osm-trcor-samsun", kind: "corridor", label: "Samsun çevre koridor", lat: 41.28, lng: 36.33, maxspeed: 90, lengthKm: 8),
        .init(id: "osm-trcor-trabzon", kind: "corridor", label: "Trabzon sahil koridor", lat: 41.00, lng: 39.72, maxspeed: 90, lengthKm: 8),
        .init(id: "osm-trcor-denizli", kind: "corridor", label: "Denizli koridor", lat: 37.77, lng: 29.08, maxspeed: 110, lengthKm: 10),
        .init(id: "osm-trcor-eskisehir", kind: "corridor", label: "Eskişehir koridor", lat: 39.78, lng: 30.52, maxspeed: 120, lengthKm: 12),
        .init(id: "osm-trcor-kayseri", kind: "corridor", label: "Kayseri koridor", lat: 38.73, lng: 35.48, maxspeed: 110, lengthKm: 10),
        .init(id: "osm-trcor-mersin", kind: "corridor", label: "Mersin O-51 koridor", lat: 36.81, lng: 34.64, maxspeed: 120, lengthKm: 12),
        .init(id: "osm-trcor-van", kind: "corridor", label: "Van çevre koridor", lat: 38.50, lng: 43.38, maxspeed: 90, lengthKm: 8),
        .init(id: "osm-trcor-erzurum", kind: "corridor", label: "Erzurum koridor", lat: 39.90, lng: 41.27, maxspeed: 90, lengthKm: 8),
        .init(id: "osm-trcor-diyarbakir", kind: "corridor", label: "Diyarbakır koridor", lat: 37.91, lng: 40.23, maxspeed: 110, lengthKm: 10),
    ]

    // MARK: - Weekly OSM (Turkey tiles)

    private static let tiles: [(s: Double, w: Double, n: Double, e: Double)] = [
        (39.8, 26.0, 42.3, 30.6), // Marmara
        (36.5, 26.0, 39.9, 30.2), // Ege
        (36.0, 27.5, 38.2, 36.6), // Akdeniz
        (37.4, 30.0, 41.1, 35.8), // İç Anadolu
        (40.4, 31.0, 42.3, 42.1), // Karadeniz
        (36.0, 35.8, 38.6, 42.2), // Güneydoğu
        (37.0, 38.0, 42.1, 44.8), // Doğu
    ]

    private static func fetchAllTiles() async -> [EtubuRouteHazard] {
        var all: [EtubuRouteHazard] = []
        for tile in tiles {
            let batch = await fetchTile(tile)
            all.append(contentsOf: batch)
            try? await Task.sleep(nanoseconds: 400_000_000)
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
        );out center;
        """
        for urlStr in endpoints {
            guard let url = URL(string: urlStr) else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
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
            let oid: String = {
                if let i = el["id"] as? Int { return "\(i)" }
                if let n = el["id"] as? NSNumber { return n.stringValue }
                return "\(lat)-\(lon)"
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
        EtubuHazardMerge.dedupePreferOfficial(list, dedupeM: 90)
    }

    private static func cacheURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Etubu", isDirectory: true)
    }

    private static func persist(_ list: [EtubuRouteHazard]) {
        guard let dir = cacheURL() else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let rows: [[String: Any]] = list.map {
            [
                "id": $0.id,
                "label": $0.label,
                "lat": $0.lat,
                "lng": $0.lng,
                "maxspeed": $0.maxspeed ?? 0,
                "lengthKm": $0.lengthKm ?? 8,
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: rows) else { return }
        try? data.write(to: dir.appendingPathComponent(cacheName), options: .atomic)
    }

    private static func loadDiskIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        if loadedDisk { return }
        loadedDisk = true
        if let dir = cacheURL() {
            let url = dir.appendingPathComponent(cacheName)
            if let data = try? Data(contentsOf: url),
               let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                memory = rows.compactMap { row in
                    guard let lat = row["lat"] as? Double, let lng = row["lng"] as? Double else { return nil }
                    let id = (row["id"] as? String) ?? "osm-trcor-\(lat)-\(lng)"
                    return EtubuRouteHazard(
                        id: id,
                        kind: "corridor",
                        label: (row["label"] as? String) ?? EtubuClusterL10n.t("warnKindCorridor"),
                        lat: lat,
                        lng: lng,
                        maxspeed: (row["maxspeed"] as? Int).flatMap { $0 > 0 ? $0 : nil },
                        lengthKm: row["lengthKm"] as? Double
                    )
                }
            }
        }
        if memory.isEmpty { memory = bundled }
    }
}
