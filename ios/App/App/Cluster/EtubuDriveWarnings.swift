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

    /// Demo drive mirror — RootView already observes this object (reliable UI refresh).
    @Published var demoActive = false
    @Published var demoKmh: Int = 0
    @Published var demoGear: String = "P"
    @Published var demoPowerKw: Int = 0

    private var timer: Timer?
    /// Last known straight-line distance per hazard — detect receding after pass.
    private var lastHazardDistM: [String: Double] = [:]
    /// Hazards touched within PASS_TOUCH_M (passed / approaching contact).
    private var touchedHazardIds: Set<String> = []

    private init() {}

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
        alertedPointIds = []
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
            hazards = hs.compactMap { Self.parseHazard($0) }
        }
        // Boş Cap hazards native EGM listesini silmesin.

        if let rh = json["remaining"] as? [[String: Any]], !rh.isEmpty {
            remainingHazards = rh.compactMap { Self.parseHazard($0, idPrefix: "rem-") }
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
        if json["corridor"] as? Bool == true, EtubuVehicleTelemetry.shared.hasActiveNavigation {
            corridorActive = true
            corridorOver = json["over"] as? Bool ?? false
            corridorAvgKmh = Self.int(json["avg"]) ?? 0
            corridorLimit = Self.int(json["limit"])
            corridorRemainLabel = (json["remain"] as? String) ?? ""
            corridorLabel = (json["corridorLabel"] as? String) ?? ""
        } else if json["corridor"] as? Bool == false, !EtubuLiveRadarMonitor.shared.corridorActive {
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
        let lat = t.latitude
        let lng = t.longitude
        let kmh = t.kmh
        let navOn = t.hasActiveNavigation
        let live = EtubuLiveRadarMonitor.shared
        let osmLocal = EtubuOsmHazardsMonitor.shared
        let wxLive = EtubuWeatherMonitor.shared

        // Rota yok (app + araç) → tüm yol uyarıları / koridor avg kapalı.
        if !navOn {
            live.tick(
                lat: lat, lng: lng, heading: t.headingDeg, kmh: kmh,
                navigationActive: false, routeCoords: []
            )
            clearAllRouteAlerts()
            maybeSpeakPrimaryWarn()
            Self.pushLiveActivityBrief()
            EtubuVehicleTelemetry.shared.publishWidgetSnapshot(primaryWarn: nil)
            return
        }

        // Güç tasarrufu: canlı OSM/radar poll yok; mevcut rota hazard sesi hafif kalabilir.
        if UserDefaults.standard.bool(forKey: "etubu.cluster.powerSave") {
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
                lat: lat, lng: lng, heading: t.headingDeg, kmh: kmh,
                navigationActive: true,
                routeCoords: routeCoords
            )
            osmLocal.tick(lat: lat, lng: lng, kmh: kmh)
            wxLive.tick(lat: lat, lng: lng)
        } else {
            live.tick(
                lat: lat, lng: lng, heading: t.headingDeg, kmh: kmh,
                navigationActive: false, routeCoords: []
            )
        }

        // OSM hız aşımı yalnız rota varken (rota üzeri bağlam).
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

        // Rota polyline varsa: rota dışı hazard'ları ele.
        if routeCoords.count >= 2 {
            pool = pool.filter { h in
                let maxOff: Double = {
                    switch h.kind {
                    case "weather": return 8_000
                    case "charge": return 450
                    default: return 160
                    }
                }()
                return Self.minDistanceToRouteM(lat: h.lat, lng: h.lng, coords: routeCoords) <= maxOff
            }
        }

        // Koridor: yalnız gerçek giriş oturumu (LiveRadarMonitor); 3.5 km yaklaşmada avg açılmaz.
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
            // While corridor overspeed is active, don't also chime a nearby radar.
            if live.corridorOver, let p = primary, p.kind != "corridor" {
                primary = live.primary ?? p
            }
        } else if corridorActive {
            clearCorridorState()
        }

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
        let heading = t.headingDeg
        var ranked: [Ranked] = []
        var nextDistMap = lastHazardDistM
        for h in pool {
            let dM = Self.haversineM(lat, lng, h.lat, h.lng)
            guard dM <= 5500 else {
                nextDistMap.removeValue(forKey: h.id)
                touchedHazardIds.remove(h.id)
                continue
            }
            if dM <= 80 { touchedHazardIds.insert(h.id) }

            let prev = lastHazardDistM[h.id]
            let approaching: Bool = {
                guard let prev else { return true }
                return dM <= prev + 12
            }()
            nextDistMap[h.id] = dM

            if let heading, heading >= 0, dM > 120 {
                let b = Self.bearingDeg(lat, lng, h.lat, h.lng)
                let diff = Self.angleDiff(b, heading)
                if diff > 70 { continue }
            }

            if touchedHazardIds.contains(h.id), dM > 160 {
                continue
            }
            if !approaching, dM > 200, let prev, dM > prev + 25 {
                continue
            }

            let stage = EtubuHazardMerge.stage(for: h.kind, distM: dM)
            guard stage != .idle else { continue }
            ranked.append(Ranked(h: h, dM: dM, stage: stage, approaching: approaching))
        }
        lastHazardDistM = nextDistMap
        ranked.sort { a, b in
            let pa = Self.warnPriority(a.h.kind)
            let pb = Self.warnPriority(b.h.kind)
            if pa != pb { return pa < pb }
            return a.dM < b.dM
        }

        let nativeQueue: [EtubuWarnItem] = ranked.prefix(4).map { r in
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

        if !live.corridorActive {
            let preferNative = !hazards.isEmpty || !remainingHazards.isEmpty
            if preferNative || queue.isEmpty || primary == nil || !(nativeQueue.contains { $0.id == primary?.id }) {
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
        } else if !nativeQueue.isEmpty {
            let rest = nativeQueue.filter { $0.kind != "corridor" || $0.id != primary?.id }
            queue = ([primary].compactMap { $0 } + rest).prefix(4).map { $0 }
        }

        // Cap tarzı: remaining = rotadaki henüz geçilmemiş / yaklaşan noktalar.
        let fullPool = hazards.isEmpty ? remainingHazards : hazards
        if !fullPool.isEmpty {
            let onRoutePool: [EtubuRouteHazard] = {
                guard routeCoords.count >= 2 else { return fullPool }
                return fullPool.filter {
                    Self.minDistanceToRouteM(lat: $0.lat, lng: $0.lng, coords: routeCoords) <= 160
                }
            }()
            remainingHazards = Self.prunePassedHazards(
                onRoutePool,
                lat: lat,
                lng: lng,
                heading: heading,
                coords: routeCoords,
                touched: &touchedHazardIds,
                lastDist: &lastHazardDistM
            )
            remainingBrief = Self.briefFromHazards(remainingHazards)
            if routeCoords.count >= 2 {
                hazards = onRoutePool
                brief = Self.briefFromHazards(onRoutePool)
            }
        } else if !ranked.isEmpty {
            remainingHazards = ranked.map(\.h)
            remainingBrief = Self.briefFromHazards(remainingHazards)
        } else if !live.corridorActive {
            primary = nil
            queue = []
            remainingHazards = []
        }

        maybeSpeakPrimaryWarn()
        Self.pushLiveActivityBrief()
        EtubuVehicleTelemetry.shared.publishWidgetSnapshot(
            primaryWarn: primary.map { "\($0.title) \($0.distanceLabel)" }
        )
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
        // Rota kapalıyken yaklaşma listesini de boşalt (harita gürültüsü olmasın).
        // hazards / remainingHazards plan verisi kalabilir; gösterim yok.
        remainingHazards = []
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
            if touched.contains(h.id), d > 160 { return false }
            // Receding fast after being closer.
            if let prev, d > prev + 40, d > 220 { return false }
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
        guard m.isFinite, m >= 0 else { return "" }
        if m >= 1000 {
            let km = m / 1000
            if km >= 10 { return String(format: "%.0f km", km) }
            return String(format: "%.1f km", km)
        }
        if m >= 100 { return "\(Int((m / 50).rounded() * 50)) m" }
        return "\(Int((m / 10).rounded() * 10)) m"
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
    /// Same OSM/radar point: one audio cue per route session (Waze/Coyote).
    private var alertedPointIds: Set<String> = []

    private func maybeSpeakPrimaryWarn() {
        applyRouteAwareAlertPolicy()
        guard !EtubuDemoDrive.isActive else { return }
        guard let item = primary else { return }

        let isOverspeed = item.kind == "corridor" && item.stage == .critical
            && (item.title == EtubuClusterL10n.slowDown || item.id.contains("-over-"))
        let isSafety = item.meta == "safety"

        if !isOverspeed, !isSafety {
            guard Self.shouldPlayApproachCue(item) else { return }
            if alertedPointIds.contains(item.id) { return }
            let now = Date()
            // Nav apps: don't stack two different chimes; one event at a time.
            if item.id != lastSpokenWarnId, now.timeIntervalSince(lastRepeatWarnAt) < 2.4 { return }
            alertedPointIds.insert(item.id)
        } else {
            let now = Date()
            if item.id == lastSpokenWarnId, now.timeIntervalSince(lastRepeatWarnAt) < 14 { return }
            lastRepeatWarnAt = now
        }

        lastSpokenWarnId = item.id
        lastSpokenWarnStage = item.stage.rawValue
        lastRepeatWarnAt = Date()
        EtubuClusterAudioBridge.playWarnCue(
            id: item.id,
            kind: item.kind,
            stage: item.stage.rawValue,
            phrase: ""
        )
    }

    /// One approach chime — not a distance countdown. Radar/tunnel earlier; urban only when close.
    private static func shouldPlayApproachCue(_ item: EtubuWarnItem) -> Bool {
        if item.kind == "charge", !EtubuVehicleTelemetry.shared.needsChargeStop {
            return false
        }
        switch item.kind {
        case "radar", "corridor", "railway", "tunnel", "climb", "winding", "weather", "road_condition", "animal":
            return item.stage == .mid || item.stage == .near || item.stage == .critical
        case "traffic_light", "crossing", "bump", "stop", "give_way":
            return item.stage == .critical || item.stage == .near
        default:
            return item.stage == .near || item.stage == .critical
        }
    }

    /// App veya araç navigasyonu açık → tüm rota uyarıları. Rota yok → yol uyarıları kapalı.
    private func applyRouteAwareAlertPolicy() {
        let t = EtubuVehicleTelemetry.shared
        let safety = extremeSafetyItems(from: t)
        let navOn = t.hasActiveNavigation

        if navOn {
            // Güvenlik (TPMS/SoC) varsa öne al; diğer rota uyarılarını silme.
            guard let s = safety.first else { return }
            if primary?.id != s.id {
                primary = s
                if !queue.contains(where: { $0.id == s.id }) {
                    queue.insert(s, at: 0)
                    if queue.count > 4 { queue = Array(queue.prefix(4)) }
                }
            }
            return
        }

        // Rota yok: radar / koridor / OSM / yol uyarıları yok. Yalnız aşırı güvenlik.
        if let s = safety.first {
            if primary?.id != s.id || queue.count != 1 {
                primary = s
                queue = [s]
            }
            clearCorridorState()
            return
        }
        clearAllRouteAlerts()
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

    private static func warnPriority(_ kind: String) -> Int {
        switch kind {
        case "corridor", "radar": return 0
        case "railway", "control": return 1
        case "tunnel", "winding", "climb", "road_condition", "animal": return 2
        case "traffic_light", "stop", "give_way", "crossing", "bump": return 3
        case "charge": return 4
        case "weather": return 5
        default: return 6
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
          if (kind === 'charge') return 1;
          if (kind === 'weather') return 2;
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
