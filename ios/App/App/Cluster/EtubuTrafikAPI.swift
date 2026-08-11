import Foundation

/// Native proxy for `https://etubu.com/api/trafik.php` — Cap WKWebView fetch is cross-origin
/// and often blocked; URLSession has no CORS. Mirrors web RouteGuard place-index build.
enum EtubuTrafikAPI {
    static let baseURL = URL(string: "https://etubu.com/api/trafik.php")!
    /// v4: force-refresh after UTF-8 inject fix (v3 caches may contain atob mojibake).
    private static let indexKey = "etubu_place_index_v4"
    private static let indexTTL: TimeInterval = 7 * 24 * 3600

    private static let metropolitanFolds: Set<String> = [
        "adana", "ankara", "antalya", "aydin", "balikesir", "bursa", "denizli",
        "diyarbakir", "erzurum", "eskisehir", "gaziantep", "hatay", "mersin",
        "istanbul", "izmir", "kayseri", "kocaeli", "konya", "malatya", "manisa",
        "kahramanmaras", "mardin", "mugla", "ordu", "sakarya", "samsun",
        "tekirdag", "trabzon", "van", "sanliurfa",
    ]

    static func get(params: [String: String]) async throws -> [String: Any] {
        var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = comps.url else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 22
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        return json
    }

    static func postCreateRoute(body: [String: Any]) async throws -> [String: Any] {
        var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "action", value: "createRoute")]
        guard let url = comps.url else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 28
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        return json
    }

    /// Build + cache place index (same shape as web `etubu_place_index_v4`).
    @discardableResult
    static func buildAndCachePlaceIndex(force: Bool = false) async throws -> Int {
        if !force, let cached = loadCachedItems(), cached.count > 100 {
            return cached.count
        }
        let citiesJson = try await get(params: ["action": "cities"])
        guard citiesJson["ok"] as? Bool == true,
              let cities = citiesJson["cities"] as? [[String: Any]] else {
            throw URLError(.cannotParseResponse)
        }
        var items: [[String: Any]] = []
        let chunk = 8
        var i = 0
        while i < cities.count {
            let slice = Array(cities[i..<min(i + chunk, cities.count)])
            try await withThrowingTaskGroup(of: (city: [String: Any], districts: [[String: Any]]).self) { group in
                for city in slice {
                    group.addTask {
                        let id = String(describing: city["Id"] ?? "")
                        do {
                            let d = try await get(params: ["action": "districts", "cityId": id])
                            let districts = (d["districts"] as? [[String: Any]]) ?? []
                            return (city, districts)
                        } catch {
                            return (city, [])
                        }
                    }
                }
                for try await part in group {
                    let cityName = jsonString(part.city["Name"])
                    let cityId = jsonString(part.city["Id"])
                    let cityFold = fold(cityName)
                    let metro = metropolitanFolds.contains(cityFold)
                    for d in part.districts {
                        let dName = jsonString(d["Name"])
                        let dFold = fold(dName)
                        let isMerkez = !metro && (dFold.contains("merkez") || dFold == cityFold || dFold == "merkez")
                        let label = isMerkez ? "\(cityName) (Merkez)" : "\(cityName) / \(dName)"
                        items.append([
                            "cityId": cityId,
                            "cityName": cityName,
                            "districtId": jsonString(d["Id"]),
                            "districtName": dName,
                            "lat": d["Latitude"] as Any,
                            "lng": d["Longitude"] as Any,
                            "label": label,
                            "isMerkez": isMerkez,
                            "isMetropolitan": metro,
                            "search": fold("\(cityName) \(dName) \(label)"),
                        ])
                    }
                }
            }
            i += chunk
        }
        let payload: [String: Any] = ["at": Date().timeIntervalSince1970 * 1000, "items": items]
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let raw = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(raw, forKey: indexKey)
        }
        return items.count
    }

    static func cachedIndexJSONString() -> String? {
        UserDefaults.standard.string(forKey: indexKey)
    }

    /// Cached item count ignoring TTL (used to unlock route UI while Cap inject catches up).
    static func cachedItemCount() -> Int {
        guard let raw = UserDefaults.standard.string(forKey: indexKey),
              let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]]
        else { return 0 }
        return items.count
    }

    /// Native autocomplete — same ranking rules as web `RouteGuard` / `__etubuSearchPlaces`.
    /// Does not require Cap WebView; uses UserDefaults cache built by `buildAndCachePlaceIndex`.
    static func searchPlaces(query: String, limit: Int = 40) -> [EtubuRoutePlace] {
        let q = fold(query)
        guard q.count >= 2, let items = loadCachedItems(ignoreTTL: true), !items.isEmpty else { return [] }
        let tokens = q.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        let maxN = max(limit, 8)

        func place(from row: [String: Any]) -> EtubuRoutePlace? {
            let label = jsonString(row["label"])
            guard !label.isEmpty else { return nil }
            let lat: Double? = {
                if let n = row["lat"] as? Double { return n }
                if let n = row["lat"] as? NSNumber { return n.doubleValue }
                if let s = row["lat"] as? String { return Double(s) }
                return nil
            }()
            let lng: Double? = {
                if let n = row["lng"] as? Double { return n }
                if let n = row["lng"] as? NSNumber { return n.doubleValue }
                if let s = row["lng"] as? String { return Double(s) }
                return nil
            }()
            return EtubuRoutePlace(
                label: label,
                cityName: jsonString(row["cityName"]),
                districtName: jsonString(row["districtName"]),
                isMyLocation: false,
                isMerkez: (row["isMerkez"] as? Bool) ?? false,
                nearLabel: "",
                lat: lat,
                lng: lng,
                districtId: jsonString(row["districtId"])
            )
        }

        let districtExact = items.filter { fold(jsonString($0["districtName"])) == q }
        if !districtExact.isEmpty {
            return districtExact
                .sorted { jsonString($0["label"]).localizedCompare(jsonString($1["label"])) == .orderedAscending }
                .prefix(max(maxN, 12))
                .compactMap(place)
        }

        let cityExact = items.filter { fold(jsonString($0["cityName"])) == q }
        if cityExact.count >= 2, tokens.count == 1 {
            return cityExact.sorted { a, b in
                let am = (a["isMerkez"] as? Bool) ?? false
                let bm = (b["isMerkez"] as? Bool) ?? false
                if am != bm { return am && !bm }
                return jsonString(a["districtName"]).localizedCompare(jsonString(b["districtName"])) == .orderedAscending
            }.compactMap(place)
        }

        if tokens.count >= 2 {
            let cityTok = tokens[0]
            let distTok = tokens.dropFirst().joined(separator: " ")
            var compound: [(score: Int, row: [String: Any])] = []
            for row in items {
                let cCity = fold(jsonString(row["cityName"]))
                let cDist = fold(jsonString(row["districtName"]))
                guard cCity == cityTok || cCity.hasPrefix(cityTok) else { continue }
                let distScore: Int
                if cDist == distTok { distScore = 100 }
                else if cDist.hasPrefix(distTok) { distScore = 80 }
                else if cDist.contains(distTok) { distScore = 50 }
                else { continue }
                compound.append((distScore, row))
            }
            if !compound.isEmpty {
                return compound
                    .sorted { $0.score > $1.score }
                    .prefix(maxN)
                    .compactMap { place(from: $0.row) }
            }
        }

        var scored: [(score: Int, row: [String: Any])] = []
        for row in items {
            let search = fold(jsonString(row["search"]).isEmpty
                ? "\(jsonString(row["cityName"])) \(jsonString(row["districtName"])) \(jsonString(row["label"]))"
                : jsonString(row["search"]))
            let cCity = fold(jsonString(row["cityName"]))
            let cDist = fold(jsonString(row["districtName"]))
            let label = fold(jsonString(row["label"]))
            var score = 0
            if cCity == q { score = 95 }
            else if cDist == q { score = 90 }
            else if label == q { score = 88 }
            else if cCity.hasPrefix(q) { score = 70 }
            else if cDist.hasPrefix(q) { score = 65 }
            else if search.hasPrefix(q) { score = 55 }
            else if search.contains(q) { score = 40 }
            else if tokens.allSatisfy({ search.contains($0) }) { score = 30 }
            else { continue }
            scored.append((score, row))
        }
        return scored
            .sorted { $0.score > $1.score }
            .prefix(maxN)
            .compactMap { place(from: $0.row) }
    }

    /// Nearest TR place to a GPS point — supplies required `fromDistrictId` for createRoute.
    static func nearestPlace(lat: Double, lng: Double, maxKm: Double = 80) -> EtubuRoutePlace? {
        guard let items = loadCachedItems(ignoreTTL: true) else { return nil }
        var best: (d: Double, row: [String: Any])?
        for row in items {
            let plat: Double? = {
                if let n = row["lat"] as? Double { return n }
                if let n = row["lat"] as? NSNumber { return n.doubleValue }
                if let s = row["lat"] as? String { return Double(s) }
                return nil
            }()
            let plng: Double? = {
                if let n = row["lng"] as? Double { return n }
                if let n = row["lng"] as? NSNumber { return n.doubleValue }
                if let s = row["lng"] as? String { return Double(s) }
                return nil
            }()
            guard let plat, let plng else { continue }
            let d = haversineKm(lat, lng, plat, plng)
            if d > maxKm { continue }
            if best == nil || d < best!.d { best = (d, row) }
        }
        guard let best else { return nil }
        let row = best.row
        let label = jsonString(row["label"])
        guard !label.isEmpty else { return nil }
        return EtubuRoutePlace(
            label: label,
            cityName: jsonString(row["cityName"]),
            districtName: jsonString(row["districtName"]),
            isMyLocation: false,
            isMerkez: (row["isMerkez"] as? Bool) ?? false,
            lat: {
                if let n = row["lat"] as? Double { return n }
                if let n = row["lat"] as? NSNumber { return n.doubleValue }
                return Double(jsonString(row["lat"]))
            }(),
            lng: {
                if let n = row["lng"] as? Double { return n }
                if let n = row["lng"] as? NSNumber { return n.doubleValue }
                return Double(jsonString(row["lng"]))
            }(),
            districtId: jsonString(row["districtId"])
        )
    }

    /// Open Charge Map via etubu.com proxy (same as web `api/chargers.php`).
    static func fetchChargersAlong(coords: [(lat: Double, lng: Double)], distanceKm: Int = 40) async -> [EtubuRouteHazard] {
        guard coords.count >= 2 else { return [] }
        let samples = sampleAlong(coords: coords, everyKm: 70, limit: 5)
        guard !samples.isEmpty else { return [] }
        guard let url = URL(string: "https://etubu.com/api/chargers.php") else { return [] }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 12
        let body: [String: Any] = [
            "distance": distanceKm,
            "points": samples.map { ["lat": $0.lat, "lng": $0.lng] },
        ]
        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["ok"] as? Bool == true,
                  let chargers = json["chargers"] as? [[String: Any]]
            else { return [] }
            var out: [EtubuRouteHazard] = []
            for c in chargers {
                let lat = (c["lat"] as? NSNumber)?.doubleValue ?? (c["lat"] as? Double)
                let lng = (c["lng"] as? NSNumber)?.doubleValue ?? (c["lng"] as? Double)
                guard let lat, let lng else { continue }
                let near = nearestRouteIndex(coords: coords, lat: lat, lng: lng)
                if near.dM > 5000 { continue }
                let kw = (c["kw"] as? NSNumber)?.intValue ?? (c["kw"] as? Int)
                let label = (c["label"] as? String) ?? (c["name"] as? String) ?? EtubuClusterL10n.t("routeChargeStation")
                out.append(EtubuRouteHazard(
                    id: (c["id"] as? String) ?? "ocm-\(lat)-\(lng)",
                    kind: "charge",
                    label: label,
                    lat: lat,
                    lng: lng,
                    kw: kw,
                    routeIdx: near.idx,
                    alongKm: alongKm(coords: coords, upTo: near.idx)
                ))
            }
            return out
        } catch {
            return []
        }
    }

    /// Open-Meteo severe weather samples along route.
    static func fetchWeatherAlong(coords: [(lat: Double, lng: Double)]) async -> [EtubuRouteHazard] {
        let samples = sampleAlong(coords: coords, everyKm: 90, limit: 3)
        guard !samples.isEmpty else { return [] }
        var out: [EtubuRouteHazard] = []
        await withTaskGroup(of: EtubuRouteHazard?.self) { group in
            for s in samples {
                group.addTask {
                    let urlStr =
                        "https://api.open-meteo.com/v1/forecast?latitude=\(s.lat)&longitude=\(s.lng)"
                        + "&current=weather_code,precipitation,wind_speed_10m&timezone=Europe%2FIstanbul"
                    guard let url = URL(string: urlStr) else { return nil }
                    var req = URLRequest(url: url)
                    req.timeoutInterval = 8
                    do {
                        let (data, resp) = try await URLSession.shared.data(for: req)
                        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let cur = json["current"] as? [String: Any]
                        else { return nil }
                        let code = (cur["weather_code"] as? NSNumber)?.intValue ?? Int(cur["weather_code"] as? Double ?? -1)
                        let wind = (cur["wind_speed_10m"] as? NSNumber)?.doubleValue ?? (cur["wind_speed_10m"] as? Double) ?? 0
                        let precip = (cur["precipitation"] as? NSNumber)?.doubleValue ?? (cur["precipitation"] as? Double) ?? 0
                        let severeCodes: Set<Int> = [45, 48, 65, 66, 67, 75, 77, 82, 85, 86, 95, 96, 97, 98, 99]
                        guard severeCodes.contains(code) || wind >= 70 || precip >= 8 else { return nil }
                        let label: String = {
                            if [95, 96, 97, 98, 99].contains(code) { return EtubuClusterL10n.t("routeWeatherStorm") }
                            if [65, 66, 67, 82].contains(code) { return EtubuClusterL10n.t("routeWeatherRain") }
                            if [75, 77, 85, 86].contains(code) { return EtubuClusterL10n.t("routeWeatherSnow") }
                            if [45, 48].contains(code) { return EtubuClusterL10n.t("routeWeatherFog") }
                            if wind >= 70 { return EtubuClusterL10n.t("routeWeatherWind") }
                            return EtubuClusterL10n.t("routeWeatherSevere")
                        }()
                        return EtubuRouteHazard(
                            id: "wx-\(s.idx)-\(code)",
                            kind: "weather",
                            label: label,
                            lat: s.lat,
                            lng: s.lng,
                            routeIdx: s.idx,
                            alongKm: alongKm(coords: coords, upTo: s.idx)
                        )
                    } catch {
                        return nil
                    }
                }
            }
            for await h in group {
                if let h { out.append(h) }
            }
        }
        return out
    }

    /// Parse EGM SpeedTunnels / Radars from createRoute `data` + optional TR highway seeds near polyline.
    static func parseOfficialHazards(
        data: [String: Any],
        coords: [(lat: Double, lng: Double)],
        includeSeeds: Bool = true
    ) -> [EtubuRouteHazard] {
        var list: [EtubuRouteHazard] = []
        if let radars = data["Radars"] as? [[String: Any]] {
            for r in radars {
                if let act = r["activity"] as? Int, act != 3 { continue }
                if let act = r["activity"] as? NSNumber, act.intValue != 3 { continue }
                let lat = (r["y"] as? NSNumber)?.doubleValue ?? (r["y"] as? Double)
                    ?? (r["lat"] as? NSNumber)?.doubleValue ?? (r["lat"] as? Double)
                let lng = (r["x"] as? NSNumber)?.doubleValue ?? (r["x"] as? Double)
                    ?? (r["lng"] as? NSNumber)?.doubleValue ?? (r["lng"] as? Double)
                guard let lat, let lng else { continue }
                let near = nearestRouteIndex(coords: coords, lat: lat, lng: lng)
                if near.dM > 2500 { continue }
                list.append(EtubuRouteHazard(
                    id: "radar-\(jsonString(r["id"]).isEmpty ? "\(lat)-\(lng)" : jsonString(r["id"]))",
                    kind: "radar",
                    label: jsonString(r["name"]).isEmpty ? EtubuClusterL10n.t("warnKindRadar") : jsonString(r["name"]),
                    lat: lat,
                    lng: lng,
                    maxspeed: (r["speedLimit"] as? NSNumber)?.intValue ?? (r["speedLimit"] as? Int),
                    routeIdx: near.idx,
                    alongKm: alongKm(coords: coords, upTo: near.idx)
                ))
            }
        }
        if let tunnels = data["SpeedTunnels"] as? [[String: Any]] {
            for tun in tunnels {
                if let act = tun["activity"] as? Int, act != 3 { continue }
                if let act = tun["activity"] as? NSNumber, act.intValue != 3 { continue }
                let lat = (tun["startLatY"] as? NSNumber)?.doubleValue ?? (tun["startLatY"] as? Double)
                let lng = (tun["startLonX"] as? NSNumber)?.doubleValue ?? (tun["startLonX"] as? Double)
                guard let lat, let lng else { continue }
                let near = nearestRouteIndex(coords: coords, lat: lat, lng: lng)
                if near.dM > 3500 { continue }
                list.append(EtubuRouteHazard(
                    id: "corridor-\(jsonString(tun["id"]).isEmpty ? "\(lat)-\(lng)" : jsonString(tun["id"]))",
                    kind: "corridor",
                    label: jsonString(tun["name"]).isEmpty ? EtubuClusterL10n.t("warnKindCorridor") : jsonString(tun["name"]),
                    lat: lat,
                    lng: lng,
                    maxspeed: (tun["speedLimit"] as? NSNumber)?.intValue ?? (tun["speedLimit"] as? Int),
                    routeIdx: near.idx,
                    alongKm: alongKm(coords: coords, upTo: near.idx)
                ))
            }
        }
        // RadarYol-style TR highway seeds (API often returns RadarCount without Radars[])
        if includeSeeds {
            for seed in trHighwaySeeds {
                let near = nearestRouteIndex(coords: coords, lat: seed.lat, lng: seed.lng)
                let maxD = seed.kind == "corridor" ? 3500.0 : 2800.0
                if near.dM > maxD { continue }
                list.append(EtubuRouteHazard(
                    id: seed.id,
                    kind: seed.kind,
                    label: seed.label,
                    lat: seed.lat,
                    lng: seed.lng,
                    maxspeed: seed.maxspeed,
                    routeIdx: near.idx,
                    alongKm: alongKm(coords: coords, upTo: near.idx)
                ))
            }
        }
        return dedupeHazards(list)
    }

    /// OSM Overpass speed cameras / section enforcement along polyline (international + TR supplement).
    static func fetchOsmCamerasAlong(
        coords: [(lat: Double, lng: Double)],
        everyKm: Double = 45,
        limitSamples: Int = 8,
        radiusM: Double = 12_000
    ) async -> [EtubuRouteHazard] {
        guard coords.count >= 2 else { return [] }
        let samples = sampleAlong(coords: coords, everyKm: everyKm, limit: limitSamples)
        guard !samples.isEmpty else { return [] }
        let endpoints = [
            "https://overpass-api.de/api/interpreter",
            "https://overpass.kumi.systems/api/interpreter",
        ]
        var merged: [EtubuRouteHazard] = []
        await withTaskGroup(of: [EtubuRouteHazard].self) { group in
            for s in samples {
                group.addTask {
                    await Self.fetchOverpassCameras(
                        lat: s.lat, lng: s.lng,
                        endpoints: endpoints,
                        radiusM: radiusM
                    )
                }
            }
            for await batch in group {
                merged.append(contentsOf: batch)
            }
        }
        var out: [EtubuRouteHazard] = []
        for h in merged {
            let near = nearestRouteIndex(coords: coords, lat: h.lat, lng: h.lng)
            let maxD = h.kind == "corridor" ? 3500.0 : 2800.0
            guard near.dM <= maxD else { continue }
            var pinned = h
            pinned.routeIdx = near.idx
            pinned.alongKm = alongKm(coords: coords, upTo: near.idx)
            out.append(pinned)
        }
        return dedupeHazards(out)
    }

    private static func fetchOverpassCameras(
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
                return parseOverpassCameras(data)
            } catch {
                continue
            }
        }
        return []
    }

    private static func parseOverpassCameras(_ data: Data) -> [EtubuRouteHazard] {
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
            let idNum = (el["id"] as? NSNumber)?.intValue ?? (el["id"] as? Int) ?? Int(lat * 1e5)
            out.append(EtubuRouteHazard(
                id: "osm-\(idNum)",
                kind: isCorridor ? "corridor" : "radar",
                label: isCorridor
                    ? EtubuClusterL10n.t("warnKindCorridor")
                    : EtubuClusterL10n.t("warnKindRadar"),
                lat: lat,
                lng: lon,
                maxspeed: maxspeed,
                lengthKm: isCorridor ? 8 : nil
            ))
        }
        return out
    }

    private static let trHighwaySeeds: [(id: String, kind: String, lat: Double, lng: Double, maxspeed: Int, label: String)] = [
        ("tem-gebze", "radar", 40.802, 29.438, 120, "Gebze TEM"),
        ("tem-izmit", "radar", 40.765, 29.94, 120, "İzmit TEM"),
        ("kor-sakarya", "corridor", 40.74, 30.35, 120, "Sakarya koridor"),
        ("kor-ankara-bati", "corridor", 39.95, 32.45, 120, "Ankara batı koridor"),
        ("o5-kemalpasa", "radar", 38.45, 27.45, 130, "Kemalpaşa O-5"),
        ("kor-o5-balikesir", "corridor", 39.55, 27.95, 130, "Balıkesir O-5 koridor"),
        ("kor-o5-manisa", "corridor", 38.72, 27.35, 130, "Manisa O-5 koridor"),
        ("kor-konya", "corridor", 38.0, 32.55, 110, "Konya koridor"),
        ("fixed-aksaray", "radar", 38.37, 34.03, 110, "Aksaray"),
        ("fixed-hadimkoy", "radar", 41.14, 28.6, 120, "Hadımköy"),
        ("kor-catalca", "corridor", 41.15, 28.35, 120, "Çatalca koridor"),
        ("fixed-silivri", "radar", 41.08, 28.25, 120, "Silivri"),
        ("fixed-aydin", "radar", 37.84, 27.84, 120, "Aydın O-31"),
        ("kor-antalya", "corridor", 37.05, 30.65, 110, "Antalya koridor"),
    ]

    private static func dedupeHazards(_ list: [EtubuRouteHazard]) -> [EtubuRouteHazard] {
        EtubuHazardMerge.dedupePreferOfficial(list)
    }

    /// Merge OSM cameras onto official EGM/seed list without cutting official points.
    static func mergeOfficialWithOsm(
        official: [EtubuRouteHazard],
        osm: [EtubuRouteHazard],
        inTurkey: Bool
    ) -> [EtubuRouteHazard] {
        let mode = EtubuHazardMerge.osmMode(
            inTurkey: inTurkey,
            officialAvailable: official.contains { EtubuHazardMerge.isEnforcement($0.kind) }
        )
        return EtubuHazardMerge.merge(official: official, osm: osm, mode: mode)
    }

    static func sampleAlong(
        coords: [(lat: Double, lng: Double)],
        everyKm: Double,
        limit: Int
    ) -> [(lat: Double, lng: Double, idx: Int)] {
        guard let first = coords.first else { return [] }
        var out: [(lat: Double, lng: Double, idx: Int)] = [(first.lat, first.lng, 0)]
        var acc = 0.0
        for i in 1..<coords.count {
            acc += haversineKm(coords[i - 1].lat, coords[i - 1].lng, coords[i].lat, coords[i].lng)
            if acc >= everyKm {
                out.append((coords[i].lat, coords[i].lng, i))
                acc = 0
                if out.count >= limit { break }
            }
        }
        if let last = coords.last {
            out.append((last.lat, last.lng, coords.count - 1))
        }
        return Array(out.prefix(limit))
    }

    static func nearestRouteIndex(
        coords: [(lat: Double, lng: Double)],
        lat: Double,
        lng: Double
    ) -> (dM: Double, idx: Int) {
        var best = (dM: Double.infinity, idx: 0)
        let step = max(1, coords.count / 500)
        var i = 0
        while i < coords.count {
            let d = haversineKm(lat, lng, coords[i].lat, coords[i].lng) * 1000
            if d < best.dM { best = (d, i) }
            i += step
        }
        return best
    }

    static func alongKm(coords: [(lat: Double, lng: Double)], upTo idx: Int) -> Double {
        guard idx > 0, coords.count > 1 else { return 0 }
        let end = min(idx, coords.count - 1)
        var sum = 0.0
        for i in 1...end {
            sum += haversineKm(coords[i - 1].lat, coords[i - 1].lng, coords[i].lat, coords[i].lng)
        }
        return sum
    }

    static func haversineKm(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = 6371.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1, sqrt(a)))
    }

    private static func loadCachedItems(ignoreTTL: Bool = false) -> [[String: Any]]? {
        guard let raw = UserDefaults.standard.string(forKey: indexKey),
              let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]],
              items.count > 100
        else { return nil }
        if !ignoreTTL {
            guard let at = json["at"] as? Double,
                  Date().timeIntervalSince1970 * 1000 - at < indexTTL * 1000
            else { return nil }
        }
        return items
    }

    private static func jsonString(_ any: Any?) -> String {
        if let s = any as? String { return s }
        if let n = any as? NSNumber { return n.stringValue }
        if let s = any { return String(describing: s) }
        return ""
    }

    private static func fold(_ s: String) -> String {
        var t = s.decomposedStringWithCanonicalMapping
            .lowercased(with: Locale(identifier: "tr_TR"))
        // Strip combining marks (NFD leftovers from iOS keyboard)
        t = t.unicodeScalars
            .filter { !$0.properties.isDiacritic }
            .map(String.init)
            .joined()
        t = t.precomposedStringWithCanonicalMapping
            .lowercased(with: Locale(identifier: "tr_TR"))
        return t
            .replacingOccurrences(of: "ğ", with: "g")
            .replacingOccurrences(of: "ü", with: "u")
            .replacingOccurrences(of: "ş", with: "s")
            .replacingOccurrences(of: "ı", with: "i")
            .replacingOccurrences(of: "ö", with: "o")
            .replacingOccurrences(of: "ç", with: "c")
            .replacingOccurrences(of: #"[^a-z0-9\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
