import Foundation
import Combine
import CoreLocation

enum EtubuVehicleSource: String {
    case tesla
    case obd
    case gps
    case demo
    case none
}

enum EtubuVehicleConnectionState: String {
    case idle
    case needsVIN
    case pairing
    case waitingForCard
    case connecting
    case connected
    case reconnecting
    case disconnected
    case failed
}

struct EtubuTireReading: Equatable {
    var psi: Double?
    var warning: Bool
}

/// Unified live vehicle state for the single-screen cluster (Tesla primary, OBD fallback).
final class EtubuVehicleTelemetry: ObservableObject {
    static let shared = EtubuVehicleTelemetry()

    @Published var connectionState: EtubuVehicleConnectionState = .needsVIN
    @Published var source: EtubuVehicleSource = .none
    @Published var deviceLabel: String = "Tesla"
    @Published var statusMessage: String = "Enter VIN to pair"
    @Published var vin: String = ""
    @Published var lastUpdateAt: Date?
    /// Yalnızca drive poll — GPS bridge / hız tazeliği buna bakar (iklim tick’i yanıltmasın).
    @Published var lastDriveAt: Date?
    /// TPMS / climate / closures son geçerli örnek.
    @Published var lastExtrasAt: Date?

    /// Demo tick — RootView dial’ının SwiftUI yenilemesi için.
    @Published var demoUIEpoch: Int = 0

    // Drive
    @Published var kmh: Int = 0
    @Published var gear: String = "P"
    @Published var powerKw: Int?
    @Published var powerHistory: [Int] = [] // last ~40 samples for sparkline
    @Published var odometerKm: Int?

    // Charge
    @Published var socPercent: Int?
    @Published var rangeKm: Int?
    @Published var chargeKw: Int?
    @Published var isCharging: Bool = false
    @Published var chargeLimitPercent: Int?
    @Published var chargerAmps: Int?
    @Published var chargerVolts: Int?
    @Published var minutesToFullCharge: Int?
    @Published var chargePortOpen: Bool?
    /// Son gerçek araç şarj örneği (demo yazmaz).
    @Published var lastChargeAt: Date?

    // Climate
    @Published var outsideC: Double?
    @Published var insideC: Double?
    @Published var climateOn: Bool?

    // Vehicle nav (Tesla active route)
    @Published var navDestination: String = ""
    @Published var navRemainKm: Double?
    @Published var navEtaMinutes: Double?
    @Published var energyAtArrivalPercent: Int?
    /// Hedef varış SoC altına düşülecekse true (EV plan).
    @Published var needsChargeStop: Bool = false
    @Published var suggestedChargeCount: Int = 0
    @Published var nextChargeAlongKm: Double?

    // Cap RouteGuard trip
    @Published var routeActive: Bool = false
    @Published var routeFrom: String = ""
    @Published var routeTo: String = ""
    /// Cap RouteGuard kalan mesafe (Tesla navRemainKm yokken EV plan için).
    @Published var capRouteRemainKm: Double?
    /// Son planlanan hedef koordinat (Maps handoff).
    @Published var routeDestLat: Double?
    @Published var routeDestLng: Double?

    // TPMS (psi)
    @Published var tpmsFL = EtubuTireReading(psi: nil, warning: false)
    @Published var tpmsFR = EtubuTireReading(psi: nil, warning: false)
    @Published var tpmsRL = EtubuTireReading(psi: nil, warning: false)
    @Published var tpmsRR = EtubuTireReading(psi: nil, warning: false)

    // Closures
    @Published var locked: Bool?
    @Published var doorFLOpen: Bool?
    @Published var doorFROpen: Bool?
    @Published var doorRLOpen: Bool?
    @Published var doorRROpen: Bool?
    @Published var frunkOpen: Bool?
    @Published var trunkOpen: Bool?
    @Published var sentryActive: Bool?
    @Published var valetMode: Bool?
    @Published var userPresent: Bool?

    // Media
    @Published var mediaTitle: String = ""
    @Published var mediaArtist: String = ""
    @Published var mediaAlbum: String = ""
    @Published var mediaSource: String = ""

    // Map (phone GPS fallback — Tesla location not in swift-tesla-ble snapshot)
    @Published var latitude: Double?
    @Published var longitude: Double?
    @Published var headingDeg: Double?

    // OBD-only extras
    @Published var rpm: Int = 0
    @Published var coolantC: Int?
    @Published var voltageV: Double?

    private init() {
        if let saved = EtubuTeslaVinStore.vin {
            vin = saved
            connectionState = .idle
            statusMessage = "Ready · \(String(saved.suffix(6)))"
            deviceLabel = "Tesla \(String(saved.suffix(6)))"
        }
        restoreLastChargeSnapshot()
        scrubDemoChargeResidueIfNeeded()
    }

    private static let lastSocKey = "etubu.charge.lastSoc"
    private static let lastRangeKey = "etubu.charge.lastRangeKm"
    private static let lastLimitKey = "etubu.charge.lastLimit"
    private static let lastChargeAtKey = "etubu.charge.lastAt"
    /// Yalnızca gerçek araç (`applyTeslaCharge`) — demo 42/180 cache’i kirletmesin.
    private static let lastSourceKey = "etubu.charge.lastSource"
    private static let vehicleSourceValue = "tesla"

    /// Demo başlamadan önceki SoC/menzil (stop’ta geri yükle).
    private var preDemoSoc: Int?
    private var preDemoRangeKm: Int?
    private var preDemoOutsideC: Double?
    private var preDemoInsideC: Double?
    private var preDemoClimateOn: Bool?

    /// SoC büyük sıçrama / ilk örnek — 2 ardışık aynı değer olmadan yayınlama.
    private var pendingSoc: Int?
    private var pendingSocHits: Int = 0
    /// Menzil büyük sıçrama onayı.
    private var pendingRangeKm: Int?
    private var pendingRangeHits: Int = 0

    /// Bağlı değilken UI’da gösterilen şarj (canlı veya son bilinen, stale değilse).
    static let chargeStaleSeconds: TimeInterval = 6 * 3600

    var displaySocPercent: Int? {
        if source == .demo { return socPercent }
        if isLiveTesla { return socPercent }
        if isChargeStale { return nil }
        return socPercent
    }
    var displayRangeKm: Int? {
        if source == .demo { return rangeKm }
        if isLiveTesla { return rangeKm }
        if isChargeStale { return nil }
        return rangeKm
    }
    var isShowingCachedCharge: Bool {
        source != .demo && !isLiveTesla && displaySocPercent != nil
    }
    var isChargeStale: Bool {
        guard socPercent != nil || rangeKm != nil else { return false }
        if isLiveTesla || source == .demo { return false }
        guard let at = lastChargeAt else { return true }
        return Date().timeIntervalSince(at) > Self.chargeStaleSeconds
    }
    /// “son 12dk” — cache SoC için.
    var chargeAgeShortLabel: String? {
        guard isShowingCachedCharge, let at = lastChargeAt else { return nil }
        let sec = Date().timeIntervalSince(at)
        if sec < 60 { return EtubuClusterL10n.t("chargeAgeJustNow") }
        if sec < 3600 {
            let m = max(1, Int(sec / 60))
            return String(format: EtubuClusterL10n.t("chargeAgeMinutes"), m)
        }
        let h = max(1, Int(sec / 3600))
        return String(format: EtubuClusterL10n.t("chargeAgeHours"), h)
    }

    /// Hız kaynağı rozeti metni.
    var speedSourceLabel: String {
        if EtubuDemoDrive.isActive || source == .demo { return EtubuClusterL10n.t("sourceDemo") }
        switch source {
        case .tesla: return EtubuClusterL10n.t("sourceTesla")
        case .obd: return EtubuClusterL10n.t("sourceOBD")
        case .gps: return EtubuClusterL10n.t("sourceGPS")
        case .demo: return EtubuClusterL10n.t("sourceDemo")
        case .none: return EtubuClusterL10n.t("sourceNone")
        }
    }

    /// Canlı Tesla bağlı ama TPMS/iklim henüz boş.
    var isAwaitingVehicleExtras: Bool {
        isLiveTesla
            && (tpmsFL.psi == nil && tpmsFR.psi == nil && tpmsRL.psi == nil && tpmsRR.psi == nil
                || outsideC == nil || insideC == nil)
    }
    var isAwaitingTPMS: Bool {
        isLiveTesla && tpmsFL.psi == nil && tpmsFR.psi == nil && tpmsRL.psi == nil && tpmsRR.psi == nil
    }
    var isAwaitingClimate: Bool {
        isLiveTesla && outsideC == nil && insideC == nil
    }

    private func restoreLastChargeSnapshot() {
        let ud = UserDefaults.standard
        // Eski demo kalıntısı (42/180) veya sourcesuz cache — gösterme / temizle.
        guard ud.string(forKey: Self.lastSourceKey) == Self.vehicleSourceValue else {
            clearPersistedChargeIfDemoPollution()
            return
        }
        if let soc = ud.object(forKey: Self.lastSocKey) as? Int {
            socPercent = min(100, max(0, soc))
        }
        if let range = ud.object(forKey: Self.lastRangeKey) as? Int, range > 0 {
            rangeKm = range
        }
        if let lim = ud.object(forKey: Self.lastLimitKey) as? Int {
            chargeLimitPercent = min(100, max(50, lim))
        }
        if let ts = ud.object(forKey: Self.lastChargeAtKey) as? Double, ts > 0 {
            lastChargeAt = Date(timeIntervalSince1970: ts)
        }
        // Stale ise UI’da gösterme (disk kalsın, sonraki canlı örnek günceller).
        if isChargeStale {
            socPercent = nil
            rangeKm = nil
        }
    }

    /// Demo bir kez 42/180 yazdıysa UserDefaults’tan sil; gerçek araç gelene kadar “—” kalsın.
    private func clearPersistedChargeIfDemoPollution() {
        let ud = UserDefaults.standard
        let soc = ud.object(forKey: Self.lastSocKey) as? Int
        let range = ud.object(forKey: Self.lastRangeKey) as? Int
        if soc == 42, range == 180 {
            ud.removeObject(forKey: Self.lastSocKey)
            ud.removeObject(forKey: Self.lastRangeKey)
            ud.removeObject(forKey: Self.lastLimitKey)
            ud.removeObject(forKey: Self.lastChargeAtKey)
            ud.removeObject(forKey: Self.lastSourceKey)
            if socPercent == 42, rangeKm == 180 {
                socPercent = nil
                rangeKm = nil
            }
        } else if ud.string(forKey: Self.lastSourceKey) != Self.vehicleSourceValue {
            // Kaynak belirsiz eski cache — UI’ya basma; anahtarları sil.
            ud.removeObject(forKey: Self.lastSocKey)
            ud.removeObject(forKey: Self.lastRangeKey)
            ud.removeObject(forKey: Self.lastSourceKey)
        }
    }

    private func persistLastChargeSnapshot() {
        let ud = UserDefaults.standard
        if let soc = socPercent { ud.set(soc, forKey: Self.lastSocKey) }
        if let range = rangeKm, range > 0 { ud.set(range, forKey: Self.lastRangeKey) }
        if let lim = chargeLimitPercent { ud.set(lim, forKey: Self.lastLimitKey) }
        let now = Date()
        lastChargeAt = now
        ud.set(now.timeIntervalSince1970, forKey: Self.lastChargeAtKey)
        ud.set(Self.vehicleSourceValue, forKey: Self.lastSourceKey)
    }

    /// Demo SoC’yi araç cache’ine yazma — yalnızca bellek içi UI.
    func persistChargeCacheForUI() {
        // no-op: demo 42/180 gerçek son şarjı ezmesin
    }

    /// Demo başlarken gerçek SoC/menzil/iklim sakla.
    func beginDemoChargeOverlay(soc: Int = 42, rangeKm: Int = 180) {
        preDemoSoc = socPercent
        preDemoRangeKm = self.rangeKm
        preDemoOutsideC = outsideC
        preDemoInsideC = insideC
        preDemoClimateOn = climateOn
        socPercent = soc
        self.rangeKm = rangeKm
        outsideC = 18
        insideC = 21
        climateOn = true
    }

    /// Demo bitince araç cache’ine / önceki değerlere dön.
    func endDemoChargeOverlay() {
        if let pre = preDemoSoc {
            socPercent = pre
        } else {
            let ud = UserDefaults.standard
            if ud.string(forKey: Self.lastSourceKey) == Self.vehicleSourceValue,
               let soc = ud.object(forKey: Self.lastSocKey) as? Int {
                socPercent = min(100, max(0, soc))
            } else if socPercent == 42 {
                socPercent = nil
            }
        }
        if let pre = preDemoRangeKm {
            rangeKm = pre
        } else {
            let ud = UserDefaults.standard
            if ud.string(forKey: Self.lastSourceKey) == Self.vehicleSourceValue,
               let range = ud.object(forKey: Self.lastRangeKey) as? Int, range > 0 {
                rangeKm = range
            } else if rangeKm == 180 {
                rangeKm = nil
            }
        }
        outsideC = preDemoOutsideC
        insideC = preDemoInsideC
        climateOn = preDemoClimateOn
        preDemoSoc = nil
        preDemoRangeKm = nil
        preDemoOutsideC = nil
        preDemoInsideC = nil
        preDemoClimateOn = nil
        if socPercent == 42, rangeKm == 180,
           UserDefaults.standard.string(forKey: Self.lastSourceKey) != Self.vehicleSourceValue {
            socPercent = nil
            rangeKm = nil
        }
        // Stale cache’i UI’dan düş
        if isChargeStale {
            socPercent = nil
            rangeKm = nil
        }
    }

    /// Demo 42/180 kalıntısını bellek + diskten temizle (araç verisi yoksa “—”).
    func scrubDemoChargeResidueIfNeeded() {
        let ud = UserDefaults.standard
        let fromVehicle = ud.string(forKey: Self.lastSourceKey) == Self.vehicleSourceValue
        if !fromVehicle, socPercent == 42, rangeKm == 180 {
            socPercent = nil
            rangeKm = nil
            ud.removeObject(forKey: Self.lastSocKey)
            ud.removeObject(forKey: Self.lastRangeKey)
            ud.removeObject(forKey: Self.lastSourceKey)
        }
    }

    var isLiveTesla: Bool { source == .tesla && connectionState == .connected }

    var anyDoorOpen: Bool {
        [doorFLOpen, doorFROpen, doorRLOpen, doorRROpen, frunkOpen, trunkOpen]
            .contains { $0 == true }
    }

    var connectionFreshnessSeconds: TimeInterval? {
        // Bağlıyken drive tazeliği öncelikli; yoksa genel lastUpdate.
        if connectionState == .connected || connectionState == .reconnecting {
            if let d = lastDriveAt { return Date().timeIntervalSince(d) }
        }
        guard let lastUpdateAt else { return nil }
        return Date().timeIntervalSince(lastUpdateAt)
    }

    var connectionQualityLabel: String {
        switch connectionState {
        case .connected:
            guard let s = connectionFreshnessSeconds else { return EtubuClusterL10n.t("connConnected") }
            if s < 3 { return EtubuClusterL10n.t("connLive") }
            if s < 8 { return EtubuClusterL10n.t("connGood") }
            if s < 20 { return EtubuClusterL10n.t("connDelayed") }
            return EtubuClusterL10n.t("connWeak")
        case .needsVIN: return EtubuClusterL10n.t("connNeedsVIN")
        case .pairing, .waitingForCard: return EtubuClusterL10n.t("connPairing")
        case .connecting: return EtubuClusterL10n.t("connConnecting")
        case .reconnecting: return EtubuClusterL10n.t("connReconnecting")
        case .failed: return EtubuClusterL10n.t("connFailed")
        case .disconnected, .idle: return EtubuClusterL10n.t("connDisconnected")
        }
    }

    /// BLE oturumu açılınca kaynak kilidi — GPS/OBD hızı ezmesin.
    func lockToTeslaSource() {
        guard !EtubuDemoDrive.isActive else { return }
        source = .tesla
        pendingSoc = nil
        pendingSocHits = 0
        pendingRangeKm = nil
        pendingRangeHits = 0
    }

    /// Geçerli Tesla lastik psi bandı (bar→psi sonrası).
    static func sanitizeTirePsi(_ psi: Double?) -> Double? {
        guard let psi, psi.isFinite else { return nil }
        // Tipik EV lastik: ~28–48 psi; biraz tolerans.
        guard psi >= 18, psi <= 55 else { return nil }
        return psi
    }

    func applyTeslaDrive(
        kmh: Int,
        gear: String,
        powerKw: Int?,
        odometerKm: Int?,
        navDestination: String?,
        navRemainKm: Double?,
        navEtaMinutes: Double?
    ) {
        guard !EtubuDemoDrive.isActive else { return }

        // İmkansız hız paketini yutma.
        guard kmh >= 0, kmh <= 280 else { return }

        // Park / creep — yalnızca P/N’de sıfırla; düşük hızı gizleme (yumuşak kadran).
        let gearU = gear.uppercased()
        let parked = gearU.hasPrefix("P") || gearU.hasPrefix("N")
        let gatedKmh: Int = {
            if parked { return 0 }
            return max(0, kmh)
        }()

        // Ani sıçrama (paket bozulması) — taze örnek varken >70 km/h delta’yı reddet.
        if let lastDriveAt,
           Date().timeIntervalSince(lastDriveAt) < 2.5,
           abs(gatedKmh - self.kmh) > 70,
           self.kmh > 0 || gatedKmh > 80 {
            return
        }

        let gatedPower: Int? = {
            guard let powerKw else { return nil }
            // Dururken HVAC gürültüsü; hareket varken düşük regen’i de göster.
            if gatedKmh == 0 { return abs(powerKw) < 8 ? 0 : powerKw }
            if abs(powerKw) < 4 { return 0 }
            if abs(powerKw) > 800 { return self.powerKw }
            return powerKw
        }()

        let kmhChanged = self.kmh != gatedKmh
        let gearChanged = self.gear != gear
        let powerChanged = self.powerKw != gatedPower
        if kmhChanged { self.kmh = gatedKmh }
        if gearChanged { self.gear = gear }
        if powerChanged { self.powerKw = gatedPower }

        // Sparkline yalnızca hareket varken — parkta history titreşimi yok.
        if gatedKmh > 0, let gatedPower {
            var hist = powerHistory
            hist.append(gatedPower)
            if hist.count > 40 { hist.removeFirst(hist.count - 40) }
            powerHistory = hist
        }
        // Odo: geriye gitmesin / tek tick’te >80 km zıplamasın.
        if let odometerKm, odometerKm > 0 {
            if let prev = self.odometerKm {
                let delta = odometerKm - prev
                if delta >= 0, delta <= 80 {
                    self.odometerKm = odometerKm
                }
            } else {
                self.odometerKm = odometerKm
            }
        }
        // Cap rota aktifken Tesla nav hedef/kalan’ı ezmesin — uygulama rotası bağımsız.
        if !routeActive {
            if let navDestination, !navDestination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.navDestination = navDestination
            }
            if let navRemainKm, navRemainKm >= 0, navRemainKm < 20_000 {
                self.navRemainKm = navRemainKm
            }
            if let navEtaMinutes, navEtaMinutes >= 0, navEtaMinutes < 10_000 {
                self.navEtaMinutes = navEtaMinutes
            }
        }
        recomputeEnergyAtArrival()
        self.source = .tesla
        let now = Date()
        lastDriveAt = now
        lastUpdateAt = now
        if kmhChanged || powerChanged || gearChanged {
            publishWidgetSnapshot()
        }
        let tripRoute = routeTo.isEmpty ? (navDestination ?? "") : routeTo
        Task { @MainActor in
            EtubuTripHistoryStore.shared.noteTelemetry(
                kmh: gatedKmh,
                gear: gear,
                odo: self.odometerKm,
                powerKw: gatedPower,
                routeTo: tripRoute
            )
        }
    }

    func applyTeslaCharge(
        soc: Int?,
        rangeKm: Int?,
        chargeKw: Int?,
        charging: Bool,
        limitPercent: Int?,
        amps: Int?,
        volts: Int?,
        minutesToFull: Int?,
        portOpen: Bool?
    ) {
        guard !EtubuDemoDrive.isActive else { return }
        if let raw = soc {
            let soc = min(100, max(0, raw))
            if let confirmed = confirmSoc(soc, charging: charging) {
                socPercent = confirmed
            }
        }
        if let rangeKm, rangeKm > 0, rangeKm < 1200 {
            if let confirmed = confirmRangeKm(rangeKm) {
                self.rangeKm = confirmed
            }
        }
        self.chargeKw = chargeKw
        isCharging = charging
        if let limitPercent, (50...100).contains(limitPercent) {
            chargeLimitPercent = limitPercent
        }
        if let amps { chargerAmps = amps }
        if let volts { chargerVolts = volts }
        if let minutesToFull { minutesToFullCharge = minutesToFull }
        if let portOpen { chargePortOpen = portOpen }
        persistLastChargeSnapshot()
        recomputeEnergyAtArrival()
        lastUpdateAt = Date()
        publishWidgetSnapshot()
    }

    /// İlk SoC veya ±2’den büyük sıçrama → 2 ardışık aynı örnek; küçük drift anında.
    private func confirmSoc(_ soc: Int, charging: Bool) -> Int? {
        if charging { pendingSoc = nil; pendingSocHits = 0; return soc }
        if let cur = socPercent, abs(cur - soc) <= 2 {
            pendingSoc = nil
            pendingSocHits = 0
            return soc
        }
        if pendingSoc == soc {
            pendingSocHits += 1
        } else {
            pendingSoc = soc
            pendingSocHits = 1
        }
        // İlk örnek (nil) veya büyük sıçrama: 2 hit.
        if pendingSocHits >= 2 {
            pendingSoc = nil
            pendingSocHits = 0
            return soc
        }
        return nil
    }

    private func confirmRangeKm(_ range: Int) -> Int? {
        if let cur = rangeKm, abs(cur - range) <= 15 {
            pendingRangeKm = nil
            pendingRangeHits = 0
            return range
        }
        if pendingRangeKm == range {
            pendingRangeHits += 1
        } else {
            pendingRangeKm = range
            pendingRangeHits = 1
        }
        if rangeKm == nil || pendingRangeHits >= 2 {
            pendingRangeKm = nil
            pendingRangeHits = 0
            return range
        }
        return nil
    }

    func applyTeslaClimate(outsideC: Double?, insideC: Double?, climateOn: Bool?) {
        var changed = false
        if let outsideC, self.outsideC != outsideC {
            self.outsideC = outsideC
            changed = true
        }
        if let insideC, self.insideC != insideC {
            self.insideC = insideC
            changed = true
        }
        if let climateOn, self.climateOn != climateOn {
            self.climateOn = climateOn
            changed = true
        }
        lastExtrasAt = Date()
        if lastUpdateAt == nil { lastUpdateAt = Date() }
        if changed { objectWillChange.send() }
    }

    func applyTeslaTPMS(fl: EtubuTireReading, fr: EtubuTireReading, rl: EtubuTireReading, rr: EtubuTireReading) {
        // Gelen psi’yi yaz; nil köşe eski iyi değeri korur (kısmi çerçeve).
        var changed = false
        func apply(_ next: EtubuTireReading, into keyPath: ReferenceWritableKeyPath<EtubuVehicleTelemetry, EtubuTireReading>) {
            if let psi = Self.sanitizeTirePsi(next.psi) {
                let reading = EtubuTireReading(psi: psi, warning: next.warning)
                if self[keyPath: keyPath] != reading {
                    self[keyPath: keyPath] = reading
                    changed = true
                }
            } else if next.warning != self[keyPath: keyPath].warning {
                var cur = self[keyPath: keyPath]
                cur.warning = next.warning
                self[keyPath: keyPath] = cur
                changed = true
            }
        }
        apply(fl, into: \.tpmsFL)
        apply(fr, into: \.tpmsFR)
        apply(rl, into: \.tpmsRL)
        apply(rr, into: \.tpmsRR)
        lastExtrasAt = Date()
        if changed { objectWillChange.send() }
    }

    func applyTeslaClosures(
        locked: Bool?,
        fl: Bool?, fr: Bool?, rl: Bool?, rr: Bool?,
        frunk: Bool?, trunk: Bool?,
        sentry: Bool?, valet: Bool?, present: Bool?
    ) {
        self.locked = locked
        doorFLOpen = fl
        doorFROpen = fr
        doorRLOpen = rl
        doorRROpen = rr
        frunkOpen = frunk
        trunkOpen = trunk
        sentryActive = sentry
        valetMode = valet
        userPresent = present
        lastExtrasAt = Date()
    }

    func applyTeslaMedia(title: String?, artist: String?, album: String?, sourceName: String?) {
        if let title { mediaTitle = title }
        if let artist { mediaArtist = artist }
        if let album { mediaAlbum = album }
        if let sourceName { mediaSource = sourceName }
        lastExtrasAt = Date()
    }

    func applyMapLocation(lat: Double?, lng: Double?, heading: Double?) {
        if let lat { latitude = lat }
        if let lng { longitude = lng }
        if let heading { headingDeg = heading }
    }

    /// Phone GPS hızı — yalnızca Tesla/OBD oturumu yokken. BLE bağlıyken asla ezmez.
    func applyGpsSpeedBridge(kmh: Int) {
        if EtubuDemoDrive.isActive { return }
        // Kesin kaynak: canlı / yeniden bağlanan Tesla → GPS hız yazmasın.
        if source == .tesla,
           connectionState == .connected
            || connectionState == .reconnecting
            || connectionState == .connecting {
            return
        }
        if source == .obd {
            let age = lastDriveAt.map { Date().timeIntervalSince($0) } ?? (connectionFreshnessSeconds ?? 999)
            if age < 0.9 { return }
        }
        let next = max(0, kmh)
        // < 5 km/h → park / GPS noise — sıfırla
        if next < 5 {
            if source == .gps || source == .none {
                if self.kmh != 0 { self.kmh = 0 }
                if source == .gps {
                    source = .gps
                    lastUpdateAt = Date()
                }
            }
            return
        }
        self.kmh = next
        if source == .none || source == .gps {
            source = .gps
            lastUpdateAt = Date()
            if connectionState == .idle || connectionState == .needsVIN || connectionState == .disconnected {
                statusMessage = EtubuClusterL10n.t("gpsSpeed")
            }
        }
        publishWidgetSnapshot()
    }

    func clearMapLocation() {
        latitude = nil
        longitude = nil
        headingDeg = nil
    }

    func applyObdFallback(kmh: Int, rpm: Int, coolant: Int?, voltage: Double?) {
        guard !EtubuDemoDrive.isActive else { return }
        guard !isLiveTesla else { return }
        // Tesla oturumu reconnect/connecting iken OBD hızı karışmasın.
        if source == .tesla,
           connectionState == .reconnecting || connectionState == .connecting {
            return
        }
        guard kmh >= 0, kmh <= 280 else { return }
        let gated = kmh < 5 ? 0 : max(0, kmh)
        if self.kmh != gated { self.kmh = gated }
        self.rpm = max(0, rpm)
        self.coolantC = coolant
        self.voltageV = voltage
        self.source = .obd
        let now = Date()
        lastDriveAt = now
        lastUpdateAt = now
        if connectionState != .connected && connectionState != .connecting && connectionState != .pairing {
            connectionState = .connected
            deviceLabel = "OBD"
            statusMessage = "OBD fallback"
        }
        publishWidgetSnapshot()
    }

    func publishWidgetSnapshot(primaryWarn: String? = nil) {
        // nil = uyarıyı silme (DriveWarnings ayrı yazar); boş string = temizle.
        EtubuSharedDriveSnapshot.publish(
            kmh: kmh,
            soc: socPercent,
            gear: gear,
            rangeKm: rangeKm,
            primaryWarn: primaryWarn,
            clearWarnIfNil: false
        )
    }

    /// Cap / demo / Tesla sonrası varış SoC + şarj planını yenile.
    func refreshEnergyPlan() {
        recomputeEnergyAtArrival()
    }

    /// Cap RouteGuard kalan km (EV plan girdisi).
    func applyCapRouteRemain(active: Bool, remainKm: Double?) {
        if active, let remainKm, remainKm > 0 {
            capRouteRemainKm = remainKm
        } else if !active {
            capRouteRemainKm = nil
        }
        recomputeEnergyAtArrival()
    }

    private func recomputeEnergyAtArrival() {
        guard let soc = socPercent, let range = rangeKm, range > 0,
              let rem = effectiveRemainKm, rem > 0 else {
            if effectiveRemainKm == nil || (effectiveRemainKm ?? 0) <= 0 {
                energyAtArrivalPercent = socPercent
            }
            Task { @MainActor in EtubuEvRoutePlanner.shared.refreshFromLiveState() }
            return
        }
        let used = min(1.0, rem / Double(range))
        energyAtArrivalPercent = max(0, Int((Double(soc) * (1.0 - used)).rounded()))
        Task { @MainActor in EtubuEvRoutePlanner.shared.refreshFromLiveState() }
    }

    /// Tesla nav veya Cap rota kalanı — Cap rota aktifken uygulama rotası öncelikli.
    var effectiveRemainKm: Double? {
        if routeActive, let c = capRouteRemainKm, c > 0 { return c }
        if let n = navRemainKm, n > 0 { return n }
        if let c = capRouteRemainKm, c > 0 { return c }
        return nil
    }

    /// Araç hareket ediyor mu (uzaktan komut kilidi).
    var isVehicleMoving: Bool {
        let g = gear.uppercased()
        if g.hasPrefix("D") || g.hasPrefix("R") { return kmh >= 1 }
        return kmh >= 3
    }

    static func barToPsi(_ bar: Double?) -> Double? {
        guard let bar else { return nil }
        return bar * 14.5038
    }

    /// Tesla bar / kPa / psi karışık gelebilir — tek psi’ye normalize.
    static func tireRawToPsi(_ raw: Double?) -> Double? {
        guard let raw, raw.isFinite, raw > 0 else { return nil }
        let psi: Double
        if raw >= 0.5, raw <= 5.5 {
            psi = raw * 14.5038 // bar
        } else if raw >= 50, raw <= 450 {
            psi = (raw / 100.0) * 14.5038 // kPa → bar → psi
        } else if raw >= 18, raw <= 55 {
            psi = raw // already psi
        } else {
            return nil
        }
        return sanitizeTirePsi(psi)
    }

    var arrivalTimeLabel: String {
        guard let mins = navEtaMinutes, mins >= 0 else { return "—" }
        let date = Date().addingTimeInterval(mins * 60)
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    var navRemainLabel: String {
        guard let km = effectiveRemainKm else { return "—" }
        if km >= 10 { return String(format: "%.0f km", km) }
        return String(format: "%.1f km", km)
    }
}
