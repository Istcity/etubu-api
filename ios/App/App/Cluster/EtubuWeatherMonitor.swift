import Foundation
import CoreLocation

/// Meteoroloji (Open-Meteo WMO) + isteğe bağlı MGM uyarı özeti.
/// Kritik olaylar rota varken HUD’a `weather` hazard olarak düşer.
@MainActor
final class EtubuWeatherMonitor: ObservableObject {
    static let shared = EtubuWeatherMonitor()

    @Published private(set) var points: [EtubuRouteHazard] = []
    @Published private(set) var lastLabel: String = ""
    @Published private(set) var dayBriefLine: String = ""
    /// Destination current weather (Island + HUD under dest).
    @Published private(set) var arrivalTempC: Int?
    @Published private(set) var arrivalSymbol: String = ""

    private var fetchCenter: CLLocationCoordinate2D?
    private var fetchedAt: Date?
    private var fetching = false
    private var arrivalCenter: CLLocationCoordinate2D?
    private var arrivalFetchedAt: Date?
    private var arrivalFetching = false

    private let refetchDistM = 8_000.0
    private let refetchAge: TimeInterval = 10 * 60

    private static let severeCodes: Set<Int> = [
        45, 48, 65, 66, 67, 75, 77, 82, 85, 86, 95, 96, 97, 98, 99,
    ]

    private init() {}

    func tick(lat: Double?, lng: Double?) {
        guard let lat, let lng, lat != 0, lng != 0 else { return }
        refreshIfNeeded(lat: lat, lng: lng)
    }

    func prefetch(lat: Double, lng: Double) {
        fetchCenter = nil
        fetchedAt = nil
        refreshIfNeeded(lat: lat, lng: lng)
    }

    func prefetchArrival(lat: Double, lng: Double) {
        arrivalCenter = nil
        arrivalFetchedAt = nil
        refreshArrivalIfNeeded(lat: lat, lng: lng)
    }

    func clearArrival() {
        guard arrivalTempC != nil || !arrivalSymbol.isEmpty else { return }
        arrivalTempC = nil
        arrivalSymbol = ""
        arrivalCenter = nil
        arrivalFetchedAt = nil
    }

    func refreshArrivalIfNeeded(lat: Double, lng: Double) {
        guard lat != 0, lng != 0 else { return }
        if arrivalFetching { return }
        let stale: Bool = {
            guard let at = arrivalFetchedAt, let c = arrivalCenter else { return true }
            if Date().timeIntervalSince(at) > refetchAge { return true }
            let moved = CLLocation(latitude: c.latitude, longitude: c.longitude)
                .distance(from: CLLocation(latitude: lat, longitude: lng))
            return moved >= refetchDistM
        }()
        guard stale else { return }
        arrivalFetching = true
        Task {
            let snap = await Self.fetchArrivalCurrent(lat: lat, lng: lng)
            await MainActor.run {
                self.arrivalFetching = false
                self.arrivalCenter = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                self.arrivalFetchedAt = Date()
                if let snap {
                    self.arrivalTempC = snap.tempC
                    self.arrivalSymbol = Self.sfSymbol(forWMO: snap.code)
                }
            }
        }
    }

    private static func fetchArrivalCurrent(lat: Double, lng: Double) async -> (code: Int, tempC: Int)? {
        let urlStr =
            "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lng)"
            + "&current=weather_code,temperature_2m&timezone=auto"
        guard let url = URL(string: urlStr) else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            let cur = json["current"] as? [String: Any] ?? [:]
            let code = (cur["weather_code"] as? NSNumber)?.intValue
                ?? Int(cur["weather_code"] as? Double ?? -1)
            let temp = (cur["temperature_2m"] as? NSNumber)?.doubleValue
                ?? (cur["temperature_2m"] as? Double)
            guard code >= 0, let temp else { return nil }
            return (code, Int(temp.rounded()))
        } catch {
            return nil
        }
    }

    static func sfSymbol(forWMO code: Int) -> String {
        switch code {
        case 0, 1: return "sun.max.fill"
        case 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67, 80, 81, 82: return "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 95, 96, 97, 98, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.sun.fill"
        }
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
            let (meteo, mgm) = await (
                Self.fetchOpenMeteo(lat: lat, lng: lng),
                Self.fetchMgmIfTurkey(lat: lat, lng: lng)
            )
            await MainActor.run {
                self.fetching = false
                self.fetchCenter = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                self.fetchedAt = Date()
                var next: [EtubuRouteHazard] = []
                if let meteo { next.append(meteo) }
                if let mgm { next.append(mgm) }
                self.points = next
                self.lastLabel = next.first?.label ?? ""
            }
            let brief = await Self.fetchDayBrief(lat: lat, lng: lng)
            await MainActor.run {
                if !brief.isEmpty { self.dayBriefLine = brief }
            }
        }
    }

    static func fetchDayBrief(lat: Double?, lng: Double?) async -> String {
        guard let lat, let lng, lat != 0, lng != 0 else { return "" }
        let urlStr =
            "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lng)"
            + "&current=weather_code,temperature_2m"
            + "&daily=weather_code,precipitation_probability_max"
            + "&forecast_days=1&timezone=auto"
        guard let url = URL(string: urlStr) else { return "" }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return "" }
            let cur = json["current"] as? [String: Any] ?? [:]
            let daily = json["daily"] as? [String: Any] ?? [:]
            let code = (cur["weather_code"] as? NSNumber)?.intValue
                ?? Int(cur["weather_code"] as? Double ?? -1)
            let dailyCodes = daily["weather_code"] as? [Any] ?? []
            let dayCode = (dailyCodes.first as? NSNumber)?.intValue
                ?? Int(dailyCodes.first as? Double ?? Double(code))
            let probs = daily["precipitation_probability_max"] as? [Any] ?? []
            let precip = (probs.first as? NSNumber)?.intValue
                ?? Int(probs.first as? Double ?? 0)
            return formatDayBrief(code: dayCode, precipChance: precip)
        } catch {
            return ""
        }
    }

    private static func formatDayBrief(code: Int, precipChance: Int) -> String {
        let sky: String = {
            if [95, 96, 97, 98, 99, 65, 66, 67, 80, 81, 82].contains(code) {
                return EtubuClusterL10n.t("wxDayRain")
            }
            if [71, 73, 75, 77, 85, 86].contains(code) {
                return EtubuClusterL10n.t("wxDaySnow")
            }
            if [1, 2, 3, 45, 48].contains(code) {
                return EtubuClusterL10n.t("wxDayCloud")
            }
            return EtubuClusterL10n.t("wxDayClear")
        }()
        if precipChance >= 20 {
            return sky + " · " + String(format: EtubuClusterL10n.t("wxDayPrecipFmt"), precipChance)
        }
        return sky
    }

    private static func fetchOpenMeteo(lat: Double, lng: Double) async -> EtubuRouteHazard? {
        let urlStr =
            "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lng)"
            + "&current=weather_code,precipitation,wind_speed_10m,wind_gusts_10m,visibility"
            + "&hourly=weather_code,precipitation,wind_speed_10m&forecast_hours=3"
            + "&timezone=auto"
        guard let url = URL(string: urlStr) else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            let cur = json["current"] as? [String: Any] ?? [:]
            var code = (cur["weather_code"] as? NSNumber)?.intValue ?? Int(cur["weather_code"] as? Double ?? -1)
            var wind = (cur["wind_speed_10m"] as? NSNumber)?.doubleValue ?? (cur["wind_speed_10m"] as? Double) ?? 0
            let gust = (cur["wind_gusts_10m"] as? NSNumber)?.doubleValue ?? (cur["wind_gusts_10m"] as? Double) ?? 0
            var precip = (cur["precipitation"] as? NSNumber)?.doubleValue ?? (cur["precipitation"] as? Double) ?? 0
            if let hourly = json["hourly"] as? [String: Any] {
                let codes = hourly["weather_code"] as? [Any] ?? []
                let winds = hourly["wind_speed_10m"] as? [Any] ?? []
                let rains = hourly["precipitation"] as? [Any] ?? []
                for i in 0..<min(3, max(codes.count, winds.count)) {
                    let c = (codes[safe: i] as? NSNumber)?.intValue ?? Int(codes[safe: i] as? Double ?? -1)
                    if severeCodes.contains(c) { code = c }
                    let w = (winds[safe: i] as? NSNumber)?.doubleValue ?? (winds[safe: i] as? Double) ?? 0
                    if w > wind { wind = w }
                    let p = (rains[safe: i] as? NSNumber)?.doubleValue ?? (rains[safe: i] as? Double) ?? 0
                    if p > precip { precip = p }
                }
            }
            wind = max(wind, gust)
            guard severeCodes.contains(code) || wind >= 70 || precip >= 8 else { return nil }
            return EtubuRouteHazard(
                id: "wx-live-\(code)",
                kind: "weather",
                label: label(code: code, wind: wind, precip: precip),
                lat: lat,
                lng: lng
            )
        } catch {
            return nil
        }
    }

    /// MGM uyarı JSON’u varsa kullan; yoksa sessizce atla.
    private static func fetchMgmIfTurkey(lat: Double, lng: Double) async -> EtubuRouteHazard? {
        guard EtubuRegion.inTurkeyBounds(lat: lat, lng: lng) else { return nil }
        let urls = [
            "https://servis.mgm.gov.tr/web/uyarilar",
            "https://www.mgm.gov.tr/FTPDATA/analiz/sonhava.json",
        ]
        for urlStr in urls {
            guard let url = URL(string: urlStr) else { continue }
            var req = URLRequest(url: url)
            req.timeoutInterval = 8
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { continue }
                if let hazard = parseMgm(data, lat: lat, lng: lng) { return hazard }
            } catch {
                continue
            }
        }
        return nil
    }

    private static func parseMgm(_ data: Data, lat: Double, lng: Double) -> EtubuRouteHazard? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let blob: String = {
            if let s = String(data: data, encoding: .utf8) { return s.lowercased() }
            return ""
        }()
        let criticalTR = ["turuncu", "kırmızı", "orange", "red", "fırtına", "tipi", "hortum", "sel"]
        let hit = criticalTR.contains { blob.contains($0) }
        guard hit else { return nil }
        var title = EtubuClusterL10n.t("routeWeatherSevere")
        if blob.contains("fırtına") || blob.contains("hortum") { title = EtubuClusterL10n.t("routeWeatherStorm") }
        else if blob.contains("kar") || blob.contains("tipi") { title = EtubuClusterL10n.t("routeWeatherSnow") }
        else if blob.contains("yağ") || blob.contains("sel") { title = EtubuClusterL10n.t("routeWeatherRain") }
        else if blob.contains("sis") { title = EtubuClusterL10n.t("routeWeatherFog") }
        else if blob.contains("rüzgar") || blob.contains("ruzgar") { title = EtubuClusterL10n.t("routeWeatherWind") }
        _ = obj
        return EtubuRouteHazard(
            id: "wx-mgm",
            kind: "weather",
            label: title,
            lat: lat,
            lng: lng
        )
    }

    static func label(code: Int, wind: Double, precip: Double) -> String {
        if [95, 96, 97, 98, 99].contains(code) { return EtubuClusterL10n.t("routeWeatherStorm") }
        if [65, 66, 67, 82].contains(code) { return EtubuClusterL10n.t("routeWeatherRain") }
        if [75, 77, 85, 86].contains(code) { return EtubuClusterL10n.t("routeWeatherSnow") }
        if [45, 48].contains(code) { return EtubuClusterL10n.t("routeWeatherFog") }
        if wind >= 70 { return EtubuClusterL10n.t("routeWeatherWind") }
        _ = precip
        return EtubuClusterL10n.t("routeWeatherSevere")
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}
