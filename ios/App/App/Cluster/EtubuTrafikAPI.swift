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
        req.timeoutInterval = 45
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
        req.timeoutInterval = 60
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

    private static func loadCachedItems() -> [[String: Any]]? {
        guard let raw = UserDefaults.standard.string(forKey: indexKey),
              let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let at = json["at"] as? Double,
              Date().timeIntervalSince1970 * 1000 - at < indexTTL * 1000,
              let items = json["items"] as? [[String: Any]],
              items.count > 100
        else { return nil }
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
