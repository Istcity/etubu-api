import Foundation
import Combine
import Capacitor
import UIKit
import CoreLocation

enum EtubuWarnStage: String {
    case idle, far, mid, near, critical
}

struct EtubuWarnItem: Equatable, Identifiable {
    var id: String
    var kind: String // radar | corridor | charge | weather | control
    var title: String
    var distanceLabel: String
    var stage: EtubuWarnStage
    var meta: String = ""
}

struct EtubuRouteHazard: Equatable, Identifiable {
    var id: String
    var kind: String
    var label: String
    var lat: Double
    var lng: Double
    var maxspeed: Int?
    var kw: Int?
    /// Index along route polyline (web RouteGuard).
    var routeIdx: Int? = nil
    /// Approx km from route start.
    var alongKm: Double? = nil
    /// Corridor length (km) — free-drive / OSM average_speed.
    var lengthKm: Double? = nil
    /// Optional corridor end pin (EGM SpeedTunnel end).
    var endLat: Double? = nil
    var endLng: Double? = nil
    /// Remaining straight-line distance label when known (e.g. "1.2 km").
    var distanceLabel: String = ""

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    var kindTitle: String { Self.kindTitle(for: kind) }

    static func kindTitle(for kind: String) -> String {
        switch kind {
        case "corridor": return EtubuClusterL10n.t("warnKindCorridor")
        case "charge": return EtubuClusterL10n.t("warnKindCharge")
        case "weather": return EtubuClusterL10n.t("warnKindWeather")
        case "control": return EtubuClusterL10n.t("warnKindControl")
        case "railway": return EtubuClusterL10n.t("warnKindRailway")
        case "traffic_light": return EtubuClusterL10n.t("warnKindTrafficLight")
        case "stop": return EtubuClusterL10n.t("warnKindStop")
        case "give_way": return EtubuClusterL10n.t("warnKindGiveWay")
        case "crossing": return EtubuClusterL10n.t("warnKindCrossing")
        case "bump": return EtubuClusterL10n.t("warnKindBump")
        case "tunnel": return EtubuClusterL10n.t("warnKindTunnel")
        case "underpass": return EtubuClusterL10n.t("warnKindUnderpass")
        case "overpass": return EtubuClusterL10n.t("warnKindOverpass")
        case "winding": return EtubuClusterL10n.t("warnKindWinding")
        case "climb": return EtubuClusterL10n.t("warnKindClimb")
        case "road_condition": return EtubuClusterL10n.t("warnKindRoadCondition")
        case "animal": return EtubuClusterL10n.t("warnKindAnimal")
        default: return EtubuClusterL10n.t("warnKindRadar")
        }
    }

    /// TTS clip composer için sabit Türkçe kök (UI dili bağımsız).
    var speakRootTR: String {
        EtubuHazardChrome.speakRootTR(kind)
    }

    /// Geriye dönük çağrılar.
    var kindTitleTR: String { kindTitle }
}

struct EtubuRouteBriefSummary: Equatable {
    var radarCount: Int = 0
    var controlCount: Int = 0
    var corridorCount: Int = 0
    var chargeCount: Int = 0
    var weatherCount: Int = 0
    var chargeNames: [String] = []
    var weatherLabels: [String] = []
    /// Tünel, hemzemin, viraj, tırmanış, yol şartı vb. (hava hariç).
    var osmCriticalCount: Int = 0

    var hasAny: Bool {
        radarCount + controlCount + corridorCount + chargeCount + weatherCount + osmCriticalCount > 0
    }

    static func isOsmCritical(_ kind: String) -> Bool {
        switch kind {
        case "railway", "tunnel", "winding", "climb", "road_condition", "animal",
             "stop", "give_way":
            return true
        default:
            return false
        }
    }

    static func from(hazards: [EtubuRouteHazard]) -> EtubuRouteBriefSummary {
        var s = EtubuRouteBriefSummary()
        for h in hazards {
            switch h.kind {
            case "corridor": s.corridorCount += 1
            case "radar": s.radarCount += 1
            case "control": s.controlCount += 1
            case "charge":
                s.chargeCount += 1
                if !h.label.isEmpty, s.chargeNames.count < 4 { s.chargeNames.append(h.label) }
            case "weather":
                s.weatherCount += 1
                if !h.label.isEmpty, s.weatherLabels.count < 4 { s.weatherLabels.append(h.label) }
            default:
                if isOsmCritical(h.kind) { s.osmCriticalCount += 1 }
                else { s.radarCount += 1 }
            }
        }
        return s
    }
}

/// Mirrors ETUBU web RouteGuard hazards + warn-reel + corridor panel (same placement logic as web).
@MainActor
final class EtubuDriveWarnings: ObservableObject {
    static let shared = EtubuDriveWarnings()

    @Published var primary: EtubuWarnItem?
    @Published var queue: [EtubuWarnItem] = []
    @Published var hazards: [EtubuRouteHazard] = []
    /// Hazards still ahead on the active route (passed ones dropped).
    @Published var remainingHazards: [EtubuRouteHazard] = []
    @Published var routeCoords: [CLLocationCoordinate2D] = []
    @Published var brief = EtubuRouteBriefSummary()
    /// Brief counts for points still ahead (Island / Live Activity).
    @Published var remainingBrief = EtubuRouteBriefSummary()

    @Published var corridorActive = false
    @Published var corridorOver = false
    @Published var corridorAvgKmh: Int = 0
    /// Vehicle speed while inside the corridor (shown next to measured average).
    @Published var corridorInstantKmh: Int = 0
    @Published var corridorLimit: Int?
    @Published var corridorRemainLabel: String = ""
    @Published var corridorLabel: String = ""
    /// Trip distance meta when not in corridor (web `#avgSpeedMeta`).
    @Published var tripDistLabel: String = ""
    /// Nearest charger — shown under the map shortcut, not in the warn twin.
    @Published var nearestCharge: EtubuRouteHazard?
    @Published var nearestChargeDistM: Double = 0

    /// Demo drive mirror — RootView already observes this object (reliable UI refresh).
    @Published var demoActive = false
    @Published var demoKmh: Int = 0
    @Published var demoGear: String = "P"
    @Published var demoPowerKw: Int = 0

    var roadHazardsAllowed: Bool {
        UserDefaults.standard.object(forKey: "etubu.alert.hazards") as? Bool ?? true
    }
    var corridorAllowed: Bool {
        UserDefaults.standard.object(forKey: "etubu.alert.corridor") as? Bool ?? true
    }
    var voiceAlertsAllowed: Bool {
        UserDefaults.standard.object(forKey: "etubu.alert.voice") as? Bool ?? true
    }
    var overspeedAllowed: Bool {
        UserDefaults.standard.object(forKey: "etubu.alert.overspeed") as? Bool ?? true
    }

    private var timer: Timer?
    /// Last known straight-line distance per hazard — detect receding after pass.
    private var lastHazardDistM: [String: Double] = [:]
    /// Hazards touched within PASS_TOUCH_M (passed / approaching contact).
    private var touchedHazardIds: Set<String> = []
    /// Arrived or clearly behind — never re-announce, even if haversine grows.
    private var passedHazardIds: Set<String> = []

    private init() {}

    var nearestChargeCaption: String? {
        guard let nearestCharge else { return nil }
        let name = nearestCharge.label.isEmpty
            ? EtubuClusterL10n.t("warnKindCharge")
            : nearestCharge.label
        let dist = EtubuHazardMerge.fmtApproachDist(nearestChargeDistM)
        return dist.isEmpty ? name : "\(name) · \(dist)"
    }

    /// Dil değişince generic HUD başlıklarını yeni dile çevir (özel isimler korunur).
    func relocalizeVisibleTitles() {
        let generics = Self.genericKindTitles()
        if var p = primary {
            if p.title.isEmpty || generics.contains(p.title) {
                p.title = EtubuRouteHazard.kindTitle(for: p.kind)
            }
            primary = p
        }
        queue = queue.map { item in
            var q = item
            if q.title.isEmpty || generics.contains(q.title) {
                q.title = EtubuRouteHazard.kindTitle(for: q.kind)
            }
            return q
        }
        if corridorActive, corridorLabel.isEmpty || generics.contains(corridorLabel) {
            corridorLabel = EtubuClusterL10n.t("warnKindCorridor")
        }
        objectWillChange.send()
    }

    private static func genericKindTitles() -> Set<String> {
        var s: Set<String> = [
            "Radar", "Hız koridoru", "Şarj istasyonu", "Hava olayı", "Kontrol",
            "RADAR", "HIZ KORİDORU", "ŞARJ", "HAVA", "KONTROL", "KRİTİK NOKTA",
            "Average speed zone", "Charging station", "Weather alert", "Checkpoint",
            "AVG SPEED", "CHARGE", "WEATHER", "CONTROL", "CRITICAL",
            "Abschnittskontrolle", "Ladestation", "Wetterwarnung", "Kontrolle",
            "ABSCHNITT", "LADEN", "WETTER", "KONTROLLE", "KRITISCH",
            "Zone de vitesse moyenne", "Borne de recharge", "Alerte météo", "Contrôle",
            "VITESSE MOY.", "MÉTÉO", "CRITIQUE",
            "Zona de velocidad media", "Estación de carga", "Alerta meteorológica",
            "VEL. MEDIA", "CARGA", "CLIMA", "CRÍTICO",
            "平均速度ゾーン", "充電ステーション", "天候警報", "取締", "レーダー", "充電", "天候", "重要",
            "Зона средней скорости", "Зарядная станция", "Погодное предупреждение",
            "РАДАР", "СР. СКОРОСТЬ", "ЗАРЯДКА", "ПОГОДА", "КОНТРОЛЬ", "КРИТИЧНО",
            "Speed camera", "Blitzer",
        ]
        for k in ["warnKindRadar", "warnKindCorridor", "warnKindCharge", "warnKindWeather", "warnKindControl",
                  "warnKickerRadar", "warnKickerCorridor", "warnKickerCharge", "warnKickerWeather",
                  "warnKickerControl", "warnKickerCritical"] {
            s.insert(EtubuClusterL10n.t(k))
        }
        return s
    }

    func clearCriticalAlerts() {
        primary = nil
        queue = []
        hazards = []
        remainingHazards = []
        lastHazardDistM = [:]
        touchedHazardIds = []
        passedHazardIds = []
        alertedPointStages = [:]
        lastSpokenWarnId = ""
        lastSpokenWarnStage = ""
        lastRepeatWarnAt = .distantPast
        brief = EtubuRouteBriefSummary()
        remainingBrief = EtubuRouteBriefSummary()
        corridorActive = false
        corridorOver = false
        corridorAvgKmh = 0
        corridorInstantKmh = 0
        corridorLimit = nil
        corridorRemainLabel = ""
        corridorLabel = ""
        tripDistLabel = ""
        // demoActive / demoKmh — clearCriticalAlerts demo sürüşünü bozmasın;
        // sadece stop() / applyDemoDrive(false) sıfırlar.
    }

    func applyDemoDrive(active: Bool, kmh: Int, gear: String, power: Int) {
        demoActive = active
        demoKmh = kmh
        demoGear = gear
        demoPowerKw = power
    }

    private var lastPollJSONHash: Int = 0
    private var pollIdleTicks = 0
    /// Debounce auto-replan when >600 m off the active polyline.
    private var lastOffRouteReplanAt = Date.distantPast

    func startPolling() {
        timer?.invalidate()
        Self.armRouteHazardHook()
        // 0.55s → 1.0s; yaklaşırken hızlanır (aşağıda).
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollOnce() }
        }
        if let t = timer { RunLoop.main.add(t, forMode: .common) }
        pollOnce()
    }

    /// Cap-side MiniMap.setRoute / setHazards stash — same hazards web places on the route.
    nonisolated static func armRouteHazardHook() {
        EtubuClusterAudioBridge.evalJS(injectScript)
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    /// Arka plan GPS callback — Timer askıdayken de radar/koridor tick.
    func tickFromLocation() {
        guard !EtubuDemoDrive.isActive else { return }
        refreshNativeProximityWarnings()
    }

    private func pollOnce() {
        // Demo kendi uyarılarını yazar — web poll boş queue ile silmesin.
        if EtubuDemoDrive.isActive { return }
        let hasNativeHazards = !hazards.isEmpty || !remainingHazards.isEmpty
        let routeQuiet = routeCoords.isEmpty && queue.isEmpty && primary == nil
            && !EtubuVehicleTelemetry.shared.routeActive && !hasNativeHazards
        if routeQuiet {
            pollIdleTicks &+= 1
            // Rota yokken her 3. tikte bir oku (≈3s).
            if pollIdleTicks % 3 != 1 {
                // OSM limit aşımı rotasız da çalışsın.
                refreshNativeProximityWarnings()
                return
            }
        } else {
            pollIdleTicks = 0
        }
        EtubuClusterAudioBridge.evalJSReturning(Self.readScript) { [weak self] raw in
            guard let self else { return }
            guard let raw, let data = raw.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                Task { @MainActor in self.refreshNativeProximityWarnings() }
                return
            }
            let hash = raw.hashValue
            Task { @MainActor in
                // Callback gecikmeli gelebilir — demo başlamışsa web sonucunu yoksay.
                if EtubuDemoDrive.isActive { return }
                if hash != self.lastPollJSONHash {
                    self.lastPollJSONHash = hash
                    self.apply(json)
                }
                // Cap JSON değişmese bile GPS yaklaşması her tikte yenilensin.
                self.refreshNativeProximityWarnings()
            }
        }
    }

    private func apply(_ json: [String: Any]) {
        if let arr = json["queue"] as? [[String: Any]] {
            let capQueue = arr.compactMap { Self.parseWarn($0) }
            if !capQueue.isEmpty {
                queue = capQueue.sorted { a, b in
                    let pa = Self.warnPriority(a.kind)
                    let pb = Self.warnPriority(b.kind)
                    if pa != pb { return pa < pb }
                    return false
                }
                primary = queue.first
            } else {
                // Cap warn-reel boş — native GPS proximity doldursun.
                queue = []
                primary = nil
            }
        }

        if let hs = json["hazards"] as? [[String: Any]], !hs.isEmpty {
            hazards = Self.sortedForDisplay(hs.compactMap { Self.parseHazard($0) })
        }
        // Boş Cap hazards native EGM listesini silmesin.

        if let rh = json["remaining"] as? [[String: Any]], !rh.isEmpty {
            remainingHazards = Self.sortedForDisplay(rh.compactMap { Self.parseHazard($0, idPrefix: "rem-") })
        } else if (json["active"] as? Bool == true) || EtubuVehicleTelemetry.shared.routeActive {
            if remainingHazards.isEmpty { remainingHazards = hazards }
        } else if !EtubuVehicleTelemetry.shared.routeActive, hazards.isEmpty {
            remainingHazards = []
        }

        if let cs = json["coords"] as? [[String: Any]], !cs.isEmpty {
            routeCoords = cs.compactMap { row in
                guard let lat = Self.double(row["lat"]), let lng = Self.double(row["lng"]) else { return nil }
                return CLLocationCoordinate2D(latitude: lat, longitude: lng)
            }
        } else if json["active"] as? Bool == false, !EtubuVehicleTelemetry.shared.routeActive {
            routeCoords = []
        }

        if let b = json["brief"] as? [String: Any] {
            let incoming = EtubuRouteBriefSummary(
                radarCount: Self.int(b["radar"]) ?? 0,
                controlCount: Self.int(b["control"]) ?? 0,
                corridorCount: Self.int(b["corridor"]) ?? 0,
                chargeCount: Self.int(b["charge"]) ?? 0,
                weatherCount: Self.int(b["weather"]) ?? 0,
                chargeNames: (b["chargeNames"] as? [String]) ?? [],
                weatherLabels: (b["weatherLabels"] as? [String]) ?? [],
                osmCriticalCount: Self.int(b["osmCritical"]) ?? 0
            )
            if incoming.hasAny || !brief.hasAny {
                brief = incoming
            }
        }

        if let rb = json["remainingBrief"] as? [String: Any] {
            remainingBrief = EtubuRouteBriefSummary(
                radarCount: Self.int(rb["radar"]) ?? 0,
                controlCount: Self.int(rb["control"]) ?? 0,
                corridorCount: Self.int(rb["corridor"]) ?? 0,
                chargeCount: Self.int(rb["charge"]) ?? 0,
                weatherCount: Self.int(rb["weather"]) ?? 0,
                chargeNames: (rb["chargeNames"] as? [String]) ?? [],
                weatherLabels: (rb["weatherLabels"] as? [String]) ?? [],
                osmCriticalCount: Self.int(rb["osmCritical"]) ?? 0
            )
        } else if !remainingHazards.isEmpty {
            remainingBrief = Self.briefFromHazards(remainingHazards)
        }

        // Derive brief counts from hazards if DOM brief not yet painted / enrich pending
        if !hazards.isEmpty, !brief.hasAny || brief.chargeCount == 0 || brief.weatherCount == 0 {
            let fromHaz = Self.briefFromHazards(hazards)
            if brief.radarCount == 0 { brief.radarCount = fromHaz.radarCount }
            if brief.corridorCount == 0 { brief.corridorCount = fromHaz.corridorCount }
            if brief.chargeCount == 0 {
                brief.chargeCount = fromHaz.chargeCount
                brief.chargeNames = fromHaz.chargeNames
            }
            if brief.weatherCount == 0 {
                brief.weatherCount = fromHaz.weatherCount
                brief.weatherLabels = fromHaz.weatherLabels
            }
            if brief.controlCount == 0 { brief.controlCount = fromHaz.controlCount }
            if brief.osmCriticalCount == 0 { brief.osmCriticalCount = fromHaz.osmCriticalCount }
        }

        // Cap koridor snapshot — yalnız gerçekten koridor içindeyken avg göster.
        if corridorAllowed, json["corridor"] as? Bool == true, EtubuVehicleTelemetry.shared.hasActiveNavigation {
            corridorActive = true
            corridorOver = json["over"] as? Bool ?? false
            corridorAvgKmh = Self.int(json["avg"]) ?? 0
            corridorLimit = Self.int(json["limit"])
            corridorRemainLabel = (json["remain"] as? String) ?? ""
            corridorLabel = (json["corridorLabel"] as? String) ?? ""
        } else if !corridorAllowed || (json["corridor"] as? Bool == false && !EtubuLiveRadarMonitor.shared.corridorActive) {
            corridorActive = false
            corridorOver = false
            corridorAvgKmh = 0
            corridorInstantKmh = 0
            corridorRemainLabel = ""
            corridorLabel = ""
            corridorLimit = nil
        }
        if let meta = json["tripMeta"] as? String, !meta.isEmpty {
            tripDistLabel = meta
        }

        let routeOn = (json["active"] as? Bool ?? false) || EtubuVehicleTelemetry.shared.routeActive
        let remainKm: Double? = {
            if let n = json["remainKm"] as? Double { return n }
            if let n = json["remainKm"] as? NSNumber { return n.doubleValue }
            if let s = json["remainKm"] as? String { return Double(s) }
            // tripMeta "123 km" fallback
            if let meta = json["tripMeta"] as? String {
                let parts = meta.replacingOccurrences(of: ",", with: ".")
                if let match = parts.range(of: #"[0-9]+(?:\.[0-9]+)?\s*km"#, options: .regularExpression) {
                    let num = parts[match].replacingOccurrences(of: "km", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    return Double(num)
                }
            }
            return nil
        }()
        EtubuVehicleTelemetry.shared.applyCapRouteRemain(active: routeOn, remainKm: remainKm)

        // Native cluster: Cap TTS kapalı — ses burada.
        maybeSpeakPrimaryWarn()

        Self.pushLiveActivityBrief()
        EtubuVehicleTelemetry.shared.publishWidgetSnapshot(
            primaryWarn: primary.map { "\($0.title) \($0.distanceLabel)" }
        )
        EtubuEvRoutePlanner.shared.refreshFromLiveState()
    }

    /// GPS + native hazard list → yalnız aktif rota/araç-nav; rota üzeri noktalar; koridor avg yalnız girişte.
    private func refreshNativeProximityWarnings() {
        guard !EtubuDemoDrive.isActive else { return }
        let t = EtubuVehicleTelemetry.shared
        let road = EtubuRoadFix.shared
        let pin = road.predictedCoordinate
        // Prefer phone RoadFix (raw or predicted) — never Tesla map pin for hazard distance
        // (vehicle LocationState is often tens of metres off the travelled lane).
        let lat = pin?.lat ?? road.latitude ?? t.latitude
        let lng = pin?.lng ?? road.longitude ?? t.longitude
        let kmh = Int((road.speedKmh ?? Double(t.kmh)).rounded())
        let heading = road.headingDeg ?? t.headingDeg
        let navOn = t.hasActiveNavigation
        let live = EtubuLiveRadarMonitor.shared
        let osmLocal = EtubuOsmHazardsMonitor.shared
        let wxLive = EtubuWeatherMonitor.shared
        if navOn, let dla = t.routeDestLat, let dln = t.routeDestLng {
            wxLive.refreshArrivalIfNeeded(lat: dla, lng: dln)
        } else if !navOn {
            wxLive.clearArrival()
        }

        // Rota yok: kalan-rota listesini kapat; yalnız gidilen yol (RoadFix) + hız limiti.
        if !navOn {
            live.tick(
                lat: lat, lng: lng, heading: heading, kmh: kmh,
                navigationActive: false, routeCoords: []
            )
            remainingHazards = []
            remainingBrief = EtubuRouteBriefSummary()
            if EtubuPremiumManager.shared.isPremium, !UserDefaults.standard.bool(forKey: "etubu.cluster.powerSave") {
                osmLocal.tick(lat: lat, lng: lng, kmh: kmh)
                applyLiveCorridor(live)
                refreshCurrentRoadProximity(
                    lat: lat, lng: lng, heading: heading, kmh: kmh,
                    pool: osmLocal.points + live.cameras, routeCoords: []
                )
                if live.corridorActive, let p = live.primary {
                    primary = p
                }
                updateNearestCharge(lat: lat, lng: lng)
            } else {
                clearAllRouteAlerts()
                updateOsmOverSpeed(kmh: kmh)
            }
            maybeSpeakPrimaryWarn()
            Self.pushLiveActivityBrief()
            EtubuVehicleTelemetry.shared.publishWidgetSnapshot(primaryWarn: primary.map { "\($0.title) \($0.distanceLabel)" })
            return
        }

        // Güç tasarrufu: canlı OSM/radar poll yok; mevcut rota hazard sesi hafif kalabilir.
        if UserDefaults.standard.bool(forKey: "etubu.cluster.powerSave") {
            live.tick(
                lat: lat, lng: lng, heading: heading, kmh: kmh,
                navigationActive: true,
                routeCoords: routeCoords
            )
            applyLiveCorridor(live)
            if let p = live.primary, EtubuHazardMerge.isEnforcement(p.kind) {
                primary = p
                if !queue.contains(where: { $0.id == p.id }) {
                    queue.insert(p, at: 0)
                }
            }
            updateNearestCharge(lat: lat, lng: lng)
            maybeSpeakPrimaryWarn()
            Self.pushLiveActivityBrief()
            return
        }

        // >600 m off active route → auto replan + refresh OSM critical points.
        if t.routeActive, let lat, let lng, routeCoords.count >= 2 {
            let offM = Self.minDistanceToRouteM(lat: lat, lng: lng, coords: routeCoords)
            if offM > 600, Date().timeIntervalSince(lastOffRouteReplanAt) > 45 {
                lastOffRouteReplanAt = Date()
                EtubuRouteBridge.replanActiveRouteFromCurrentLocation(reason: "off-route-\(Int(offM))m")
            }
        }

        if EtubuPremiumManager.shared.isPremium {
            EtubuTrCorridorStore.refreshIfNeeded()
            // Karma canlı: radar (uzun menzil) + OSM yerel kritik — aynı anda.
            live.tick(
                lat: lat, lng: lng, heading: heading, kmh: kmh,
                navigationActive: true,
                routeCoords: routeCoords
            )
            osmLocal.tick(lat: lat, lng: lng, kmh: kmh)
            wxLive.tick(lat: lat, lng: lng)
        } else {
            live.tick(
                lat: lat, lng: lng, heading: heading, kmh: kmh,
                navigationActive: false, routeCoords: []
            )
        }

        // Hız limiti rota olmasa da RoadFix ile devam eder.
        updateOsmOverSpeed(kmh: kmh)

        // Rota hazard + canlı kameralar birleşik havuz (EGM primary, OSM supplement/led).
        var pool = remainingHazards.isEmpty ? hazards : remainingHazards
        if !EtubuPremiumManager.shared.isPremium {
            // Ücretsiz: yalnızca OSM hız levhası — radar/koridor/şarj/hava yok.
            hazards = []
            remainingHazards = []
            brief = EtubuRouteBriefSummary()
            remainingBrief = EtubuRouteBriefSummary()
            queue = queue.filter { $0.meta == "OSM" }
            if primary?.meta != "OSM" { primary = queue.first }
            clearCorridorState()
            maybeSpeakPrimaryWarn()
            Self.pushLiveActivityBrief()
            return
        }

        let officialBase = pool.filter { !EtubuHazardMerge.isOsmSource($0) }
        let priorOsm = pool.filter { EtubuHazardMerge.isOsmSource($0) }
        let liveOfficial = live.cameras.filter { !EtubuHazardMerge.isOsmSource($0) }
        let liveOsm = live.cameras.filter { EtubuHazardMerge.isOsmSource($0) }
        // OSM led — EGM yok; TR koridor cache + canlı OSM aynı havuz.
        pool = EtubuHazardMerge.merge(
            official: [],
            osm: priorOsm + liveOsm + osmLocal.points + officialBase + liveOfficial,
            mode: .led
        )
        pool.append(contentsOf: wxLive.points)
        pool = pool.filter { EtubuOsmHazardsMonitor.isRoadTrafficWarning($0) }
        pool = pool.filter { $0.kind != "charge" }
        pool = pool.filter { !passedHazardIds.contains($0.id) }

        // Rota polyline varsa: rota dışı hazard'ları ele.
        if routeCoords.count >= 2, let lat, let lng {
            pool = pool.filter { h in
                let maxOff: Double = {
                    switch h.kind {
                    case "weather": return 8_000
                    case "corridor": return 3_200
                    case "radar", "control": return 420
                    case "tunnel", "railway": return 320
                    default: return 280
                    }
                }()
                return Self.minDistanceToRouteM(lat: h.lat, lng: h.lng, coords: routeCoords) <= maxOff
            }
        }

        // Koridor: yalnız gerçek giriş oturumu (LiveRadarMonitor); 3.5 km yaklaşmada avg açılmaz.
        applyLiveCorridor(live)

        guard let lat, let lng else {
            maybeSpeakPrimaryWarn()
            Self.pushLiveActivityBrief()
            return
        }
        guard !pool.isEmpty || t.hasActiveNavigation || live.corridorActive else {
            if !live.corridorActive {
                primary = nil
                queue = []
            }
            maybeSpeakPrimaryWarn()
            Self.pushLiveActivityBrief()
            return
        }

        struct Ranked {
            var h: EtubuRouteHazard
            var dM: Double
            var stage: EtubuWarnStage
            var approaching: Bool
        }
        var ranked: [Ranked] = []
        var nextDistMap = lastHazardDistM
        for h in pool {
            if passedHazardIds.contains(h.id) { continue }
            let straight = Self.haversineM(lat, lng, h.lat, h.lng)
            let along = routeCoords.count >= 2
                ? Self.remainingAlongRouteM(lat: lat, lng: lng, destLat: h.lat, destLng: h.lng, coords: routeCoords)
                : nil
            let dM: Double = {
                guard let along, along.isFinite, along >= 0 else { return straight }
                if along > straight * 4 { return straight }
                return along
            }()
            guard dM <= 5500 else {
                nextDistMap.removeValue(forKey: h.id)
                touchedHazardIds.remove(h.id)
                continue
            }
            if dM <= 28 || straight <= 22 { touchedHazardIds.insert(h.id) }

            let prev = lastHazardDistM[h.id]
            let approaching: Bool = {
                guard let prev else { return true }
                return dM <= prev + 8
            }()
            nextDistMap[h.id] = dM

            // 1. Doğrudan veya teğet geçiş tespiti
            if dM <= 22 || straight <= 18 {
                markPassed(h.id)
                continue
            }

            // 2. Yön (Heading) Kontrolü — 65° sıkı tolerans ile karşı şerit filtreleme
            if let heading, heading >= 0 {
                let b = Self.bearingDeg(lat, lng, h.lat, h.lng)
                let diff = Self.angleDiff(b, heading)
                // Nokta arkaya düştüyse (açı > 85° ve mesafe artıyorsa) hemen geçildi işaretle
                if diff > 85, let prev, dM > prev + 3 {
                    markPassed(h.id)
                    continue
                }
                // Karşı istikamet ve yan tali yol filtreleme (maksimum 65° tolerans)
                if dM > 35 {
                    let tol = 65.0
                    if diff > tol { continue }
                }
            }

            if touchedHazardIds.contains(h.id), !approaching, dM > 30 {
                markPassed(h.id)
                continue
            }
            if !approaching, let prev, dM > prev + 12, dM > 30 {
                markPassed(h.id)
                continue
            }

            let stageRaw = EtubuHazardMerge.stage(for: h.kind, distM: dM)
            let stage: EtubuWarnStage = {
                if stageRaw != .idle { return stageRaw }
                if h.kind == "corridor", dM <= 2_200 { return .far }
                if EtubuHazardMerge.isEnforcement(h.kind), dM <= 800 { return .far }
                return .idle
            }()
            guard stage != .idle else { continue }
            ranked.append(Ranked(h: h, dM: dM, stage: stage, approaching: approaching))
        }
        lastHazardDistM = nextDistMap

        // Dinamik Önceliklendirme: Mesafeye ve aciliyete göre sıralama
        ranked.sort { a, b in
            let pa = Self.warnPriority(a.h.kind, distM: a.dM)
            let pb = Self.warnPriority(b.h.kind, distM: b.dM)
            if pa != pb { return pa < pb }
            return a.dM < b.dM
        }

        let roadRanked = ranked.filter { $0.h.kind != "weather" }

        func item(from r: Ranked) -> EtubuWarnItem {
            let lim = r.h.maxspeed.map { " · \($0)" } ?? ""
            return EtubuWarnItem(
                id: r.h.id,
                kind: r.h.kind,
                title: r.h.label.isEmpty ? r.h.kindTitle : r.h.label,
                distanceLabel: Self.fmtDist(r.dM) + lim,
                stage: r.stage,
                meta: r.h.maxspeed.map { "lim \($0)" } ?? ""
            )
        }

        var nativeQueue: [EtubuWarnItem] = roadRanked.prefix(3).map { item(from: $0) }
        if nativeQueue.count < 4, let wx = ranked.first(where: { $0.h.kind == "weather" }) {
            nativeQueue.append(item(from: wx))
        }
        nativeQueue = Array(nativeQueue.prefix(4))

        if live.corridorActive {
            if !nativeQueue.isEmpty {
                let rest = nativeQueue.filter { $0.kind != "corridor" || $0.id != primary?.id }
                queue = ([primary].compactMap { $0 } + rest).prefix(4).map { $0 }
            }
        } else {
            if !nativeQueue.isEmpty {
                queue = nativeQueue
                primary = nativeQueue.first
            } else if let p = live.primary {
                primary = p
                queue = [p]
            } else {
                primary = nil
                queue = []
            }
        }

        // Cap tarzı: remaining = rotadaki henüz geçilmemiş / yaklaşan noktalar.
        let fullPool = hazards.isEmpty ? remainingHazards : hazards
        if !fullPool.isEmpty {
            let onRoutePool: [EtubuRouteHazard] = {
                guard routeCoords.count >= 2 else { return fullPool }
                return fullPool.filter { h in
                    let maxOff: Double = {
                        switch h.kind {
                        case "weather": return 8_000
                        case "charge": return 450
                        case "corridor": return 3_200
                        case "radar", "control": return 420
                        case "tunnel", "railway": return 320
                        default: return 280
                        }
                    }()
                    return Self.minDistanceToRouteM(lat: h.lat, lng: h.lng, coords: routeCoords) <= maxOff
                }
            }()
            remainingHazards = Self.sortedForDisplay(
                Self.prunePassedHazards(
                    onRoutePool,
                    lat: lat,
                    lng: lng,
                    heading: heading,
                    coords: routeCoords,
                    touched: &touchedHazardIds,
                    lastDist: &lastHazardDistM
                )
            )
            remainingBrief = Self.briefFromHazards(remainingHazards)
            if routeCoords.count >= 2 {
                hazards = Self.sortedForDisplay(onRoutePool)
                brief = Self.briefFromHazards(hazards)
                remainingHazards = remainingHazards.filter { !passedHazardIds.contains($0.id) }
                remainingBrief = Self.briefFromHazards(remainingHazards)
            }
            // Yalnız hâlâ yaklaşan OSM — geçilmişleri remaining'e geri sokma.
            let liveIds = Set(ranked.map(\.h.id))
            let extraRoad = pool.filter { h in
                liveIds.contains(h.id)
                    && !passedHazardIds.contains(h.id)
                    && h.kind != "weather"
            }
            if !extraRoad.isEmpty {
                remainingHazards = Self.sortedForDisplay(
                    EtubuHazardMerge.dedupePreferOfficial(remainingHazards + extraRoad)
                )
                remainingBrief = Self.briefFromHazards(remainingHazards)
            }
        } else if !ranked.isEmpty {
            remainingHazards = Self.sortedForDisplay(ranked.map(\.h))
            remainingBrief = Self.briefFromHazards(remainingHazards)
        } else if !live.corridorActive {
            primary = nil
            queue = []
            remainingHazards = []
        }

        updateNearestCharge(lat: lat, lng: lng)
        maybeSpeakPrimaryWarn()
        Self.pushLiveActivityBrief()
        EtubuVehicleTelemetry.shared.publishWidgetSnapshot(
            primaryWarn: primary.map { "\($0.title) \($0.distanceLabel)" }
        )
    }

    /// Rota yokken yalnız gidilen yol (RoadFix heading konisi, ~450 m).
    private func refreshCurrentRoadProximity(
        lat: Double?,
        lng: Double?,
        heading: Double?,
        kmh: Int,
        pool: [EtubuRouteHazard],
        routeCoords: [CLLocationCoordinate2D]
    ) {
        updateOsmOverSpeed(kmh: kmh)
        guard let lat, let lng else { return }
        struct Ranked {
            var h: EtubuRouteHazard
            var dM: Double
            var stage: EtubuWarnStage
        }
        var ranked: [Ranked] = []
        var nextDist = lastHazardDistM
        for h in pool {
            if passedHazardIds.contains(h.id) { continue }
            guard EtubuOsmHazardsMonitor.isRoadTrafficWarning(h) else { continue }
            let dM = Self.haversineM(lat, lng, h.lat, h.lng)
            let maxD: Double = {
                switch h.kind {
                case "corridor": return 2_200
                case "radar", "control": return 800
                default: return 450
                }
            }()
            guard dM <= maxD else {
                nextDist.removeValue(forKey: h.id)
                continue
            }
            let prev = lastHazardDistM[h.id]
            nextDist[h.id] = dM
            if dM <= 22 {
                markPassed(h.id)
                continue
            }
            if let heading, heading >= 0, dM > 28 {
                let b = Self.bearingDeg(lat, lng, h.lat, h.lng)
                let tol = EtubuHazardMerge.isEnforcement(h.kind) ? 90.0 : 70.0
                if Self.angleDiff(b, heading) > tol { continue }
            }
            if let prev, dM > prev + 12, dM > 35 {
                markPassed(h.id)
                continue
            }
            let stageRaw = EtubuHazardMerge.stage(for: h.kind, distM: dM)
            let stage: EtubuWarnStage = {
                if stageRaw != .idle { return stageRaw }
                if h.kind == "corridor", dM <= 2_200 { return .far }
                if EtubuHazardMerge.isEnforcement(h.kind), dM <= 800 { return .far }
                return .idle
            }()
            guard stage != .idle else { continue }
            ranked.append(Ranked(h: h, dM: dM, stage: stage))
        }
        lastHazardDistM = nextDist
        ranked.sort { a, b in
            let pa = Self.warnPriority(a.h.kind)
            let pb = Self.warnPriority(b.h.kind)
            if pa != pb { return pa < pb }
            return a.dM < b.dM
        }
        let enforcement = ranked.filter { EtubuHazardMerge.isEnforcement($0.h.kind) }
        let others = ranked.filter { !EtubuHazardMerge.isEnforcement($0.h.kind) }
        func item(_ r: Ranked) -> EtubuWarnItem {
            EtubuWarnItem(
                id: r.h.id,
                kind: r.h.kind,
                title: r.h.label.isEmpty ? r.h.kindTitle : r.h.label,
                distanceLabel: Self.fmtDist(r.dM),
                stage: r.stage,
                meta: r.h.maxspeed.map { "lim \($0)" } ?? ""
            )
        }
        if corridorActive {
            let rest = others.prefix(3).map { item($0) }
            queue = ([primary].compactMap { $0 } + rest).prefix(4).map { $0 }
            updateNearestCharge(lat: lat, lng: lng)
            return
        }
        let nativeQueue: [EtubuWarnItem]
        if let e = enforcement.first {
            nativeQueue = [item(e)] + others.prefix(2).map { item($0) }
        } else if let p = EtubuLiveRadarMonitor.shared.primary, EtubuHazardMerge.isEnforcement(p.kind) {
            nativeQueue = [p] + others.prefix(2).map { item($0) }
        } else {
            nativeQueue = Array(others.prefix(3).map { item($0) })
        }
        if primary?.meta == "OSM", nativeQueue.isEmpty {
            updateNearestCharge(lat: lat, lng: lng)
            return
        }
        queue = nativeQueue
        primary = nativeQueue.first
        updateNearestCharge(lat: lat, lng: lng)
        _ = routeCoords
        _ = kmh
    }

    private func markPassed(_ id: String) {
        passedHazardIds.insert(id)
        touchedHazardIds.remove(id)
        lastHazardDistM.removeValue(forKey: id)
        if passedHazardIds.count > 140 {
            passedHazardIds = Set(Array(passedHazardIds).prefix(80))
        }
        if primary?.id == id {
            primary = queue.first { $0.id != id }
            queue.removeAll { $0.id == id }
        }
        if lastSpokenWarnId == id {
            lastSpokenWarnId = ""
            lastSpokenWarnStage = ""
        }
    }

    private func updateNearestCharge(lat: Double?, lng: Double?) {
        let planner = EtubuEvRoutePlanner.shared
        var candidates = planner.suggestedStops
        let pool = remainingHazards.isEmpty ? hazards : remainingHazards
        candidates.append(contentsOf: pool.filter { $0.kind == "charge" })
        candidates.append(contentsOf: EtubuOsmHazardsMonitor.shared.points.filter { $0.kind == "charge" })
        var seen = Set<String>()
        candidates = candidates.filter { seen.insert($0.id).inserted }
        guard !candidates.isEmpty else {
            nearestCharge = nil
            nearestChargeDistM = 0
            return
        }
        guard let lat, let lng else {
            nearestCharge = candidates.first
            nearestChargeDistM = 0
            return
        }
        let best = candidates.min(by: { a, b in
            Self.haversineM(lat, lng, a.lat, a.lng) < Self.haversineM(lat, lng, b.lat, b.lng)
        })
        nearestCharge = best
        if let best {
            nearestChargeDistM = Self.haversineM(lat, lng, best.lat, best.lng)
        } else {
            nearestChargeDistM = 0
        }
    }

    private func applyLiveCorridor(_ live: EtubuLiveRadarMonitor) {
        if live.corridorActive {
            corridorActive = true
            corridorOver = live.corridorOver
            corridorAvgKmh = live.corridorAvgKmh
            corridorInstantKmh = live.corridorInstantKmh
            corridorLimit = live.corridorLimit
            corridorRemainLabel = live.corridorRemainLabel
            corridorLabel = live.corridorLabel
            if let p = live.primary {
                primary = p
                if !queue.contains(where: { $0.id == p.id }) {
                    queue.insert(p, at: 0)
                }
            }
            if live.corridorOver, let p = primary, p.kind != "corridor" {
                primary = live.primary ?? p
            }
        } else if corridorActive {
            clearCorridorState()
        }
    }

    private func clearCorridorState() {
        corridorActive = false
        corridorOver = false
        corridorAvgKmh = 0
        corridorInstantKmh = 0
        corridorRemainLabel = ""
        corridorLabel = ""
        corridorLimit = nil
    }

    private func clearAllRouteAlerts() {
        primary = nil
        queue = []
        clearCorridorState()
        tripDistLabel = ""
        remainingHazards = []
        nearestCharge = nil
        nearestChargeDistM = 0
    }

    private func updateOsmOverSpeed(kmh: Int) {
        let lim = EtubuOsmSpeedLimit.shared.limitKmh
        guard let lim, lim > 0, kmh >= EtubuOsmSpeedLimit.movingKmhThreshold else { return }
        guard kmh > lim + 5 else { return }
        // Daha güçlü radar/koridor uyarısı varken OSM aşımını bastırma.
        if let p = primary, p.kind == "radar" || p.kind == "corridor", p.stage == .critical || p.stage == .near {
            return
        }
        if primary == nil || queue.isEmpty || primary?.meta == "OSM" {
            let item = EtubuWarnItem(
                id: "osm-over-\(lim)",
                kind: "radar",
                title: EtubuClusterL10n.slowDown,
                distanceLabel: "\(kmh) / \(lim)",
                stage: kmh > lim + 15 ? .critical : .near,
                meta: "OSM"
            )
            primary = item
            queue = [item]
        }
    }

    private static func haversineM(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        EtubuTrafikAPI.haversineKm(lat1, lon1, lat2, lon2) * 1000
    }

    /// Remaining metres along the polyline from the vehicle to the hazard.
    /// Nil when the hazard is clearly behind the user on the line.
    private static func remainingAlongRouteM(
        lat: Double, lng: Double,
        destLat: Double, destLng: Double,
        coords: [CLLocationCoordinate2D]
    ) -> Double? {
        guard coords.count >= 2 else { return nil }
        var uIdx = 0
        var uBest = Double.greatestFiniteMagnitude
        var hIdx = 0
        var hBest = Double.greatestFiniteMagnitude
        for (i, c) in coords.enumerated() {
            let du = haversineM(lat, lng, c.latitude, c.longitude)
            if du < uBest { uBest = du; uIdx = i }
            let dh = haversineM(destLat, destLng, c.latitude, c.longitude)
            if dh < hBest { hBest = dh; hIdx = i }
        }
        if hIdx + 1 < uIdx { return nil }
        if uIdx == hIdx {
            return haversineM(lat, lng, destLat, destLng)
        }
        var sum = 0.0
        var i = uIdx
        while i < hIdx {
            let a = coords[i]
            let b = coords[i + 1]
            sum += haversineM(a.latitude, a.longitude, b.latitude, b.longitude)
            i += 1
        }
        sum += haversineM(coords[hIdx].latitude, coords[hIdx].longitude, destLat, destLng)
        if uIdx + 1 < coords.count {
            let seg = haversineM(
                coords[uIdx].latitude, coords[uIdx].longitude,
                coords[uIdx + 1].latitude, coords[uIdx + 1].longitude
            )
            let toNext = haversineM(lat, lng, coords[uIdx + 1].latitude, coords[uIdx + 1].longitude)
            if seg > 1, toNext < seg {
                sum = max(0, sum - (seg - toNext))
            }
        }
        return sum
    }

    /// Minimum distance from point to route polyline (metres).
    private static func minDistanceToRouteM(
        lat: Double, lng: Double,
        coords: [CLLocationCoordinate2D]
    ) -> Double {
        guard coords.count >= 2 else { return .greatestFiniteMagnitude }
        var best = Double.greatestFiniteMagnitude
        // Sample vertices + mid-segments for a cheap off-route check.
        for i in 0..<coords.count {
            let c = coords[i]
            best = min(best, haversineM(lat, lng, c.latitude, c.longitude))
            if i + 1 < coords.count {
                let n = coords[i + 1]
                let midLat = (c.latitude + n.latitude) * 0.5
                let midLng = (c.longitude + n.longitude) * 0.5
                best = min(best, haversineM(lat, lng, midLat, midLng))
            }
            if best < 80 { return best }
        }
        return best
    }

    /// Cap / web RouteGuard: drop passed points via routeIdx, heading-behind, or touch+distance.
    private static func prunePassedHazards(
        _ list: [EtubuRouteHazard],
        lat: Double,
        lng: Double,
        heading: Double?,
        coords: [CLLocationCoordinate2D],
        touched: inout Set<String>,
        lastDist: inout [String: Double]
    ) -> [EtubuRouteHazard] {
        guard !list.isEmpty else { return list }
        let userIdx: Int = {
            guard coords.count >= 2 else { return 0 }
            var best = 0
            var bestD = Double.greatestFiniteMagnitude
            for (i, c) in coords.enumerated() {
                let d = haversineM(lat, lng, c.latitude, c.longitude)
                if d < bestD {
                    bestD = d
                    best = i
                }
            }
            return best
        }()
        return list.filter { h in
            let d = haversineM(lat, lng, h.lat, h.lng)
            if d <= 22 { return false }
            if d <= 80 { touched.insert(h.id) }
            let prev = lastDist[h.id]
            lastDist[h.id] = d

            if let idx = h.routeIdx {
                if idx < userIdx - 1 {
                    // Behind on polyline.
                    if let heading, heading >= 0 {
                        let b = bearingDeg(lat, lng, h.lat, h.lng)
                        if angleDiff(b, heading) > 95 { return false }
                    } else if d > 150 {
                        return false
                    }
                }
            }
            // Touched and distancing → remove from ahead list.
            if touched.contains(h.id), d > 40 { return false }
            // Receding fast after being closer.
            if let prev, d > prev + 15, d > 35 { return false }
            // Far behind absolute.
            if d > 25_000 { return false }
            return true
        }
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
        EtubuHazardMerge.fmtApproachDist(m)
    }

    private static func parseHazard(_ row: [String: Any], idPrefix: String = "") -> EtubuRouteHazard? {
        guard let lat = double(row["lat"]), let lng = double(row["lng"]) else { return nil }
        let kind = (row["kind"] as? String) ?? "radar"
        let label = (row["label"] as? String) ?? ""
        return EtubuRouteHazard(
            id: (row["id"] as? String) ?? "\(idPrefix)\(kind)-\(lat),\(lng)",
            kind: kind,
            label: label,
            lat: lat,
            lng: lng,
            maxspeed: int(row["maxspeed"]),
            kw: int(row["kw"]),
            routeIdx: int(row["routeIdx"]),
            alongKm: double(row["alongKm"]),
            distanceLabel: (row["dist"] as? String) ?? ""
        )
    }

    private var lastSpokenWarnId = ""
    private var lastSpokenWarnStage = ""
    private var lastRepeatWarnAt = Date.distantPast
    /// Point and stage audio tracking: pointId -> set of alerted stages (approach / overspeed_near)
    private var alertedPointStages: [String: Set<String>] = [:]

    private func maybeSpeakPrimaryWarn() {
        applyRouteAwareAlertPolicy()
        guard !EtubuDemoDrive.isActive else { return }
        guard let item = primary else { return }
        if passedHazardIds.contains(item.id) { return }

        let isOverspeedCorridor = item.kind == "corridor" && item.stage == .critical
            && (item.title == EtubuClusterL10n.slowDown || item.id.contains("-over-"))
        let isSafety = item.meta == "safety"

        if isOverspeedCorridor || isSafety {
            let now = Date()
            if item.id == lastSpokenWarnId, now.timeIntervalSince(lastRepeatWarnAt) < 12 { return }
            lastRepeatWarnAt = now
            lastSpokenWarnId = item.id
            lastSpokenWarnStage = item.stage.rawValue
            EtubuClusterAudioBridge.playWarnCue(
                id: item.id,
                kind: item.kind,
                stage: item.stage.rawValue,
                phrase: ""
            )
            return
        }

        // Standart Yol Uyarıları & Radarlar için 2 Kademeli Ses Mantığı:
        guard Self.shouldPlayApproachCue(item) else { return }
        var stages = alertedPointStages[item.id] ?? []

        // Kademe 1: İlk Yaklaşma İkazı (800m - 1000m)
        let isFirstApproach = !stages.contains("approach")
        
        // Kademe 2: Radara/Noktaya 260m kala Hız Aşımı Sürüyorsa Acil 2. İkaz
        let isNearStage = item.stage == .near || item.stage == .critical
        let curKmh = EtubuVehicleTelemetry.shared.kmh
        let limit = EtubuOsmSpeedLimit.shared.limitKmh ?? 0
        let isOverSpeedAtNear = isNearStage && limit > 0 && curKmh > (limit + 3)
        let shouldPlayOverspeedReminder = isOverSpeedAtNear && !stages.contains("overspeed_near")

        if isFirstApproach {
            stages.insert("approach")
            alertedPointStages[item.id] = stages
            lastSpokenWarnId = item.id
            lastSpokenWarnStage = item.stage.rawValue
            lastRepeatWarnAt = Date()
            EtubuClusterAudioBridge.playWarnCue(
                id: item.id,
                kind: item.kind,
                stage: item.stage.rawValue,
                phrase: ""
            )
        } else if shouldPlayOverspeedReminder {
            stages.insert("overspeed_near")
            alertedPointStages[item.id] = stages
            lastSpokenWarnId = item.id
            lastSpokenWarnStage = "critical"
            lastRepeatWarnAt = Date()
            // 2. Kademe Acil İkaz Tonu
            EtubuWarnVoice.playKindCue(kind: item.kind, urgent: true)
        }
    }

    /// One approach chime — not a distance countdown. Radar/tunnel earlier; urban only when close.
    private static func shouldPlayApproachCue(_ item: EtubuWarnItem) -> Bool {
        if item.kind == "charge", !EtubuVehicleTelemetry.shared.needsChargeStop {
            return false
        }
        if EtubuOsmHazardsMonitor.mutedWarnKinds.contains(item.kind) { return false }
        switch item.kind {
        case "radar", "corridor", "railway", "tunnel", "climb", "winding", "weather", "road_condition", "animal":
            return item.stage == .mid || item.stage == .near || item.stage == .critical
        case "traffic_light", "stop", "give_way":
            return item.stage == .critical || item.stage == .near
        case "bump":
            return item.stage == .critical || item.stage == .near || item.stage == .mid
        default:
            return item.stage == .near || item.stage == .critical
        }
    }

    /// App veya araç navigasyonu açık → şarj + kritik. Rota yok → yalnız gidilen yol + hız limiti.
    private func applyRouteAwareAlertPolicy() {
        let t = EtubuVehicleTelemetry.shared
        let safety = extremeSafetyItems(from: t)
        guard let s = safety.first else { return }
        // Radar / koridor HUD'da iken güvenlik uyarısı onları kesmesin — kuyruğa ekle.
        if let p = primary, EtubuHazardMerge.isEnforcement(p.kind) {
            if !queue.contains(where: { $0.id == s.id }) {
                queue.insert(s, at: min(1, queue.count))
                if queue.count > 4 { queue = Array(queue.prefix(4)) }
            }
            return
        }
        if primary?.id != s.id {
            primary = s
            if !queue.contains(where: { $0.id == s.id }) {
                queue.insert(s, at: 0)
                if queue.count > 4 { queue = Array(queue.prefix(4)) }
            }
        }
    }

    private func extremeSafetyItems(from t: EtubuVehicleTelemetry) -> [EtubuWarnItem] {
        var items: [EtubuWarnItem] = []
        let tires: [(String, EtubuTireReading)] = [
            ("FL", t.tpmsFL), ("FR", t.tpmsFR), ("RL", t.tpmsRL), ("RR", t.tpmsRR),
        ]
        if let low = tires.first(where: { ($0.1.bar ?? 99) < 2.5 }) {
            let bar = low.1.bar.map { String(format: "%.1f bar", $0) } ?? ""
            items.append(EtubuWarnItem(
                id: "safety-tpms-\(low.0)",
                kind: "control",
                title: EtubuClusterL10n.t("warnTpmsLow"),
                distanceLabel: "\(low.0) \(bar)",
                stage: .critical,
                meta: "safety"
            ))
        }
        if let soc = t.displaySocPercent, soc < 5 {
            items.append(EtubuWarnItem(
                id: "safety-soc",
                kind: "charge",
                title: EtubuClusterL10n.t("warnBatteryCritical"),
                distanceLabel: "\(soc)%",
                stage: .critical,
                meta: "safety"
            ))
        }
        return items
    }

    private static var lastLivePushMs: Double = 0
    private static func pushLiveActivityBrief() {
        guard #available(iOS 16.2, *) else { return }
        let now = Date().timeIntervalSince1970 * 1000
        guard now - lastLivePushMs > 800 else { return }
        lastLivePushMs = now
        Task { await EtubuLiveActivityController.publishCurrent() }
    }

    private static func parseWarn(_ row: [String: Any]) -> EtubuWarnItem? {
        let title = (row["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stage = EtubuWarnStage(rawValue: (row["stage"] as? String) ?? "idle") ?? .idle
        guard stage != .idle || !title.isEmpty else { return nil }
        guard !title.isEmpty else { return nil }
        let kind = (row["kind"] as? String) ?? "radar"
        return EtubuWarnItem(
            id: (row["id"] as? String) ?? "\(kind)-\(title)",
            kind: kind,
            title: title,
            distanceLabel: (row["dist"] as? String) ?? "",
            stage: stage == .idle ? .far : stage,
            meta: (row["meta"] as? String) ?? ""
        )
    }

    nonisolated private static func warnPriority(_ kind: String, distM: Double = .infinity) -> Int {
        // Acil yakın tehlikeler (<160m kasis, kırmızı ışık, dur, hemzemin geçit) en yüksek önceliğe (-1) yükselir.
        if distM < 160 {
            switch kind {
            case "bump", "traffic_light", "stop", "give_way", "railway", "crossing", "road_condition", "animal":
                return -1
            default:
                break
            }
        }
        switch kind {
        case "corridor", "radar": return 0
        case "railway", "control": return 1
        case "tunnel", "underpass", "overpass", "winding", "climb", "road_condition", "animal": return 2
        case "traffic_light", "stop", "give_way", "crossing", "bump": return 3
        case "weather": return 4
        case "charge": return 5
        default: return 3
        }
    }

    /// Road warnings first, charge stations second, weather last. Then along-route order.
    nonisolated static func sortedForDisplay(_ hazards: [EtubuRouteHazard]) -> [EtubuRouteHazard] {
        hazards.sorted { a, b in
            let pa = warnPriority(a.kind)
            let pb = warnPriority(b.kind)
            if pa != pb { return pa < pb }
            let aa = a.alongKm ?? Double(a.routeIdx ?? 1_000_000)
            let bb = b.alongKm ?? Double(b.routeIdx ?? 1_000_000)
            if aa != bb { return aa < bb }
            return a.label < b.label
        }
    }

    private static func briefFromHazards(_ hazards: [EtubuRouteHazard]) -> EtubuRouteBriefSummary {
        EtubuRouteBriefSummary.from(hazards: hazards)
    }

    private static func double(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String { return Double(s) }
        return nil
    }

    private static func int(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let d = any as? Double { return Int(d) }
        if let n = any as? NSNumber { return n.intValue }
        if let s = any as? String { return Int(s) }
        return nil
    }

    /// Patches MiniMap.setRoute / setHazards so Cap can read the same hazard list web places on the route.
    private static let injectScript = """
    (function(){
      if (window.__etubuRouteHook) return;
      window.__etubuRouteHook = true;
      window.__etubuRouteState = window.__etubuRouteState || { hazards: [], coords: [], at: 0 };
      function stashHazards(h) {
        if (!Array.isArray(h)) return;
        window.__etubuRouteState.hazards = h.map(function(x){
          return {
            id: x.id || ((x.kind||'radar') + '-' + x.lat + ',' + x.lng),
            kind: x.kind || 'radar',
            label: x.label || x.name || '',
            lat: +x.lat, lng: +x.lng,
            maxspeed: x.maxspeed != null ? +x.maxspeed : null,
            kw: x.kw != null ? +x.kw : null,
            routeIdx: x.routeIdx != null ? +x.routeIdx : null
          };
        }).filter(function(x){ return Number.isFinite(x.lat) && Number.isFinite(x.lng); });
        window.__etubuRouteState.at = Date.now();
      }
      function stashCoords(c) {
        if (!Array.isArray(c)) return;
        window.__etubuRouteState.coords = c.map(function(p){
          if (Array.isArray(p)) return { lng: +p[0], lat: +p[1] };
          return { lng: +(p.lng != null ? p.lng : p.x), lat: +(p.lat != null ? p.lat : p.y) };
        }).filter(function(x){ return Number.isFinite(x.lat) && Number.isFinite(x.lng); });
      }
      function wrapMiniMap() {
        if (typeof MiniMap === 'undefined' || !MiniMap || MiniMap.__etubuWrapped) return !!MiniMap?.__etubuWrapped;
        var sr = MiniMap.setRoute;
        var sh = MiniMap.setHazards;
        if (typeof sr === 'function') {
          MiniMap.setRoute = function(coords, hazards) {
            stashCoords(coords);
            if (arguments.length > 1) stashHazards(hazards);
            return sr.apply(this, arguments);
          };
        }
        if (typeof sh === 'function') {
          MiniMap.setHazards = function(hazards) {
            stashHazards(hazards);
            return sh.apply(this, arguments);
          };
        }
        MiniMap.__etubuWrapped = true;
        return true;
      }
      wrapMiniMap();
      var n = 0;
      var t = setInterval(function(){
        if (wrapMiniMap() || ++n > 48) clearInterval(t);
      }, 250);
    })();
    """

    private static let readScript = """
    (function(){
      try {
        if (!window.__etubuRouteHook) {
          /* inject may race — no-op flag check */
        }
        var st = window.__etubuRouteState || { hazards: [], coords: [] };
        var hazards = (st.hazards || []).map(function(x){
          return {
            id: x.id || ((x.kind||'radar') + '-' + x.lat + ',' + x.lng),
            kind: x.kind || 'radar',
            label: x.label || x.name || '',
            lat: +x.lat, lng: +x.lng,
            maxspeed: x.maxspeed != null ? +x.maxspeed : null,
            kw: x.kw != null ? +x.kw : null,
            routeIdx: x.routeIdx != null ? +x.routeIdx : null,
            alongKm: x.alongKm != null ? +x.alongKm : null,
            dist: x.dist || ''
          };
        });
        var coords = st.coords || [];

        function nearestIdx(lat, lng) {
          if (!coords.length) return 0;
          var best = 0, bestD = Infinity;
          for (var i = 0; i < coords.length; i++) {
            var dLat = (coords[i].lat - lat) * Math.PI/180;
            var dLon = (coords[i].lng - lng) * Math.PI/180;
            var a = Math.sin(dLat/2)*Math.sin(dLat/2) +
              Math.cos(lat*Math.PI/180)*Math.cos(coords[i].lat*Math.PI/180)*Math.sin(dLon/2)*Math.sin(dLon/2);
            var d = 2*6371000*Math.asin(Math.sqrt(a));
            if (d < bestD) { bestD = d; best = i; }
          }
          return best;
        }
        function alongKmForIdx(idx) {
          if (!coords.length || idx <= 0) return 0;
          var sum = 0;
          var n = Math.min(idx, coords.length - 1);
          for (var i = 1; i <= n; i++) {
            var a = coords[i-1], b = coords[i];
            var dLat = (b.lat - a.lat) * Math.PI/180;
            var dLon = (b.lng - a.lng) * Math.PI/180;
            var aa = Math.sin(dLat/2)*Math.sin(dLat/2) +
              Math.cos(a.lat*Math.PI/180)*Math.cos(b.lat*Math.PI/180)*Math.sin(dLon/2)*Math.sin(dLon/2);
            sum += 2*6371000*Math.asin(Math.sqrt(aa));
          }
          return Math.round(sum / 100) / 10;
        }
        function fmtDist(m) {
          if (!Number.isFinite(m) || m < 0) return '';
          var stepped;
          if (m >= 5000) stepped = Math.max(10000, Math.floor(m / 10000) * 10000);
          else if (m >= 2000) stepped = Math.max(1000, Math.floor(m / 1000) * 1000);
          else if (m >= 300) stepped = Math.max(100, Math.floor(m / 100) * 100);
          else if (m >= 100) stepped = Math.max(50, Math.floor(m / 50) * 50);
          else stepped = Math.max(10, Math.floor(m / 10) * 10);
          if (stepped >= 1000) {
            var km = stepped / 1000;
            return (Number.isInteger(km) ? km : km.toFixed(1)) + ' km';
          }
          return Math.round(stepped) + ' m';
        }

        function warnPri(kind) {
          if (kind === 'corridor' || kind === 'radar') return 0;
          if (kind === 'railway' || kind === 'control') return 1;
          if (kind === 'tunnel' || kind === 'underpass' || kind === 'overpass'
              || kind === 'winding' || kind === 'climb' || kind === 'road_condition'
              || kind === 'animal') return 2;
          if (kind === 'traffic_light' || kind === 'stop' || kind === 'give_way'
              || kind === 'crossing' || kind === 'bump') return 3;
          if (kind === 'weather') return 4;
          if (kind === 'charge') return 5;
          return 3;
        }

        // Enrich alongKm for detail lists
        hazards = hazards.map(function(h){
          if (h.alongKm == null && h.routeIdx != null) h.alongKm = alongKmForIdx(h.routeIdx);
          return h;
        });

        function inferKind(title, meta, fallback) {
          var s = ((title||'') + ' ' + (meta||'')).toLocaleLowerCase('tr-TR');
          if (/koridor|corridor|ortalama/.test(s)) return 'corridor';
          if (/şarj|sarj|charge|kwh|\\bkw\\b|ocm|zes|trugo/.test(s)) return 'charge';
          if (/hava|yağmur|yagmur|sis|fırtına|firtina|kar|buz|rüzgar|ruzgar|weather|storm|fog/.test(s)) return 'weather';
          if (/kontrol|control/.test(s)) return 'control';
          return fallback || 'radar';
        }

        var reel = document.getElementById('warnReel');
        var track = document.getElementById('warnReelTrack');
        var stage = (reel && !reel.hidden) ? (reel.dataset.stage || 'far') : 'idle';
        var primaryKind = 'radar';
        if (reel && reel.className) {
          var m = String(reel.className).match(/is-kind-([a-z]+)/);
          if (m) primaryKind = m[1];
        }

        var queue = [];
        if (track && reel && !reel.hidden) {
          var cards = track.querySelectorAll('.warn-reel-item, .warn-reel-card');
          for (var i = 0; i < cards.length && queue.length < 4; i++) {
            var card = cards[i];
            var title = (card.querySelector('.warn-reel-kicker, .warn-reel-title')?.textContent
              || card.getAttribute('data-title') || '').trim();
            var dist = (card.querySelector('.warn-reel-dist')?.textContent
              || card.getAttribute('data-dist') || '').trim();
            var meta = (card.querySelector('.warn-reel-meta')?.textContent || '').trim();
            if (!title && !dist) continue;
            var kind = i === 0 ? primaryKind : inferKind(title, meta, primaryKind);
            queue.push({
              id: card.getAttribute('data-id') || (kind + '-' + title + '-' + dist + '-' + i),
              kind: kind,
              title: title.slice(0, 80),
              dist: dist.slice(0, 24),
              meta: meta.slice(0, 100),
              stage: i === 0 ? stage : 'far'
            });
          }
        }

        // Prefer RouteGuard.listAhead when GPS known — same placement window as web
        var lat = null, lng = null;
        try {
          var loc = JSON.parse(localStorage.getItem('etubu_last_map_location') || '{}');
          if (Number.isFinite(loc.lat) && Number.isFinite(loc.lng)) { lat = loc.lat; lng = loc.lng; }
        } catch (e) {}
        if (lat == null && coords.length) {
          lat = coords[0].lat; lng = coords[0].lng;
        }
        if (window.RouteGuard && typeof RouteGuard.listAhead === 'function' && lat != null) {
          try {
            var ahead = RouteGuard.listAhead(lat, lng, null, 4) || [];
            if (ahead.length) {
              queue = ahead.map(function(it, idx){
                return {
                  id: it.id || ('rg-' + idx),
                  kind: it.kind || 'radar',
                  title: (it.title || '').slice(0, 80),
                  dist: (it.dist || '').slice(0, 24),
                  distM: it.distM != null ? +it.distM : null,
                  meta: (it.meta || '').slice(0, 100),
                  stage: it.stage || (idx === 0 ? stage : 'far'),
                  pri: warnPri(it.kind || 'radar')
                };
              });
              queue.sort(function(a, b){
                return (a.pri - b.pri) || ((a.distM||1e12) - (b.distM||1e12));
              });
              if (queue[0] && stage !== 'idle') queue[0].stage = stage;
            }
          } catch (e2) {}
        }

        // Remaining hazards — drop passed points along the route
        var remaining = hazards.slice();
        if (lat != null && Number.isFinite(lat) && hazards.length) {
          var userIdx = nearestIdx(lat, lng);
          remaining = hazards.filter(function(h){
            if (h.routeIdx != null && Number.isFinite(h.routeIdx)) {
              return h.routeIdx >= userIdx - 1;
            }
            // fallback: still ahead if farther than ~80m behind heading proxy — keep if within 25km
            var dLat = (h.lat - lat) * Math.PI/180;
            var dLon = (h.lng - lng) * Math.PI/180;
            var a = Math.sin(dLat/2)*Math.sin(dLat/2) +
              Math.cos(lat*Math.PI/180)*Math.cos(h.lat*Math.PI/180)*Math.sin(dLon/2)*Math.sin(dLon/2);
            var d = 2*6371000*Math.asin(Math.sqrt(a));
            return d < 25000;
          }).map(function(h){
            var dLat = (h.lat - lat) * Math.PI/180;
            var dLon = (h.lng - lng) * Math.PI/180;
            var a = Math.sin(dLat/2)*Math.sin(dLat/2) +
              Math.cos(lat*Math.PI/180)*Math.cos(h.lat*Math.PI/180)*Math.sin(dLon/2)*Math.sin(dLon/2);
            var d = 2*6371000*Math.asin(Math.sqrt(a));
            h.dist = fmtDist(d);
            if (h.alongKm == null && h.routeIdx != null) h.alongKm = alongKmForIdx(h.routeIdx);
            return h;
          });
          // Prefer RouteGuard.listAhead ids when available for tighter remaining set
          try {
            if (window.RouteGuard && typeof RouteGuard.listAhead === 'function') {
              var aheadAll = RouteGuard.listAhead(lat, lng, null, 80) || [];
              if (aheadAll.length) {
                var ids = {};
                aheadAll.forEach(function(it){ if (it.id) ids[it.id] = it; });
                var filtered = remaining.filter(function(h){ return ids[h.id]; });
                if (filtered.length) {
                  remaining = filtered.map(function(h){
                    var it = ids[h.id];
                    if (it && it.dist) h.dist = it.dist;
                    return h;
                  });
                }
              }
            }
          } catch (e4) {}
        }

        function countBrief(list) {
          var b = { radar: 0, control: 0, corridor: 0, charge: 0, weather: 0, chargeNames: [], weatherLabels: [] };
          (list || []).forEach(function(h){
            if (h.kind === 'corridor') b.corridor++;
            else if (h.kind === 'charge') { b.charge++; if (h.label && b.chargeNames.length < 4) b.chargeNames.push(h.label); }
            else if (h.kind === 'weather') { b.weather++; if (h.label && b.weatherLabels.length < 4) b.weatherLabels.push(h.label); }
            else if (h.kind === 'control') b.control++;
            else b.radar++;
          });
          return b;
        }

        // Brief counts — same cards RouteGuard.renderBrief paints
        var brief = { radar: 0, control: 0, corridor: 0, charge: 0, weather: 0, chargeNames: [], weatherLabels: [] };
        var cardsEl = document.querySelectorAll('.route-brief-cards > div');
        if (cardsEl && cardsEl.length >= 5) {
          function num(el){ var em = el && el.querySelector('em'); return em ? parseInt(em.textContent, 10) || 0 : 0; }
          brief.radar = num(cardsEl[0]);
          brief.control = num(cardsEl[1]);
          brief.corridor = num(cardsEl[2]);
          brief.charge = num(cardsEl[3]);
          brief.weather = num(cardsEl[4]);
        }
        var chargeBlock = document.querySelector('.route-brief-charge span');
        if (chargeBlock && chargeBlock.textContent) {
          brief.chargeNames = chargeBlock.textContent.split('·').map(function(s){ return s.trim(); }).filter(Boolean).slice(0, 4);
        }
        var wxBlock = document.querySelector('.route-brief-weather span');
        if (wxBlock && wxBlock.textContent) {
          brief.weatherLabels = wxBlock.textContent.split('·').map(function(s){ return s.trim(); }).filter(Boolean).slice(0, 4);
        }
        // Fallback from stashed hazards (official + seed + enrich)
        if (!brief.radar && !brief.corridor && !brief.charge && !brief.weather && hazards.length) {
          brief = countBrief(hazards);
        }
        var remainingBrief = countBrief(remaining);

        var avgP = document.getElementById('avgSpeedPanel');
        var avgV = document.getElementById('avgSpeedValue');
        var avgM = document.getElementById('avgSpeedMeta');
        var avgB = document.getElementById('avgSpeedBadge');
        var corridor = !!(avgP && avgP.classList.contains('is-corridor'));
        var over = !!(avgP && avgP.classList.contains('is-over'));
        var avg = avgV ? parseInt(avgV.textContent, 10) || 0 : 0;
        var limit = null;
        var remain = '';
        var corridorLabel = avgB ? (avgB.textContent || '').trim() : '';
        var metaTxt = avgM ? (avgM.textContent || '') : '';
        var tripMeta = '';
        var lim = metaTxt.match(/(\\d+)\\s*(?:km\\/h|kmh)/i);
        if (lim) limit = parseInt(lim[1], 10);
        var rem = metaTxt.match(/([\\d.]+\\s*km|[\\d]+\\s*m)/i);
        if (rem) remain = rem[1];
        try {
          if (window.RadarAlert && RadarAlert.getCorridorSnapshot) {
            var snap = RadarAlert.getCorridorSnapshot(avg);
            if (snap && snap.active) {
              corridor = true;
              over = !!snap.over;
              avg = Math.round(snap.avg || avg);
              if (snap.limit != null) limit = snap.limit;
              if (snap.remainM != null) {
                remain = snap.remainM >= 1000 ? (Math.round(snap.remainM/100)/10) + ' km' : Math.round(snap.remainM) + ' m';
              }
              if (snap.label) corridorLabel = snap.label;
            }
          }
        } catch (e3) {}
        // Web: outside corridor, avgSpeedValue = tripAvg and meta = trip km
        if (!corridor) {
          tripMeta = metaTxt.trim();
          remain = '';
          limit = null;
          corridorLabel = '';
          over = false;
        }

        var active = !!(window.RouteGuard && RouteGuard.isActive && RouteGuard.isActive());
        var remainKm = null;
        var routeTotalKm = null;
        if (coords.length >= 2) {
          var totalM = 0;
          for (var ri = 1; ri < coords.length; ri++) {
            var ca = coords[ri-1], cb = coords[ri];
            var dLatR = (cb.lat - ca.lat) * Math.PI/180;
            var dLonR = (cb.lng - ca.lng) * Math.PI/180;
            var aaR = Math.sin(dLatR/2)*Math.sin(dLatR/2) +
              Math.cos(ca.lat*Math.PI/180)*Math.cos(cb.lat*Math.PI/180)*Math.sin(dLonR/2)*Math.sin(dLonR/2);
            totalM += 2*6371000*Math.asin(Math.sqrt(aaR));
          }
          routeTotalKm = Math.round(totalM / 100) / 10;
          if (lat != null && Number.isFinite(lat)) {
            var uIdx = nearestIdx(lat, lng);
            var alongM = 0;
            for (var ai = 1; ai <= uIdx && ai < coords.length; ai++) {
              var aa = coords[ai-1], bb = coords[ai];
              var dLatA = (bb.lat - aa.lat) * Math.PI/180;
              var dLonA = (bb.lng - aa.lng) * Math.PI/180;
              var aaa = Math.sin(dLatA/2)*Math.sin(dLatA/2) +
                Math.cos(aa.lat*Math.PI/180)*Math.cos(bb.lat*Math.PI/180)*Math.sin(dLonA/2)*Math.sin(dLonA/2);
              alongM += 2*6371000*Math.asin(Math.sqrt(aaa));
            }
            remainKm = Math.max(0, Math.round((totalM - alongM) / 100) / 10);
          } else {
            remainKm = routeTotalKm;
          }
        }
        return JSON.stringify({
          active: active,
          stage: queue.length ? (queue[0].stage || stage) : 'idle',
          queue: queue,
          hazards: hazards.slice(0, 120),
          remaining: remaining.slice(0, 80),
          coords: coords.length > 400 ? coords.filter(function(_,i){ return i % Math.ceil(coords.length/400) === 0; }) : coords,
          brief: brief,
          remainingBrief: remainingBrief,
          corridor: corridor, over: over, avg: avg, limit: limit,
          remain: remain, corridorLabel: corridorLabel, tripMeta: tripMeta,
          remainKm: remainKm, routeTotalKm: routeTotalKm
        });
      } catch (e) {
        return JSON.stringify({ stage: 'idle', queue: [], hazards: [], remaining: [], coords: [], brief: {}, remainingBrief: {} });
      }
    })();
    """
}
