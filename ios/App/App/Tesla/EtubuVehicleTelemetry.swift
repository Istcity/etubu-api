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

    /// Tesla TPMS payload is bar; UI stores psi. 2.5 bar ≈ 36.3 psi.
    var bar: Double? {
        psi.map { $0 / 14.5038 }
    }
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
    /// Boş paket değil — gerçek hız/vites/güç uygulandığı an. Donmuş HUD tespiti.
    @Published var lastDriveValueAt: Date?
    /// TPMS / climate / closures son geçerli örnek.
    @Published var lastExtrasAt: Date?

    /// SoC epoch — UI forces refresh even when percent value is unchanged after re-poll.
    @Published var chargeEpoch: Int = 0
    @Published var tpmsEpoch: Int = 0
    @Published var climateEpoch: Int = 0
    /// True only after a BLE charge packet with real SoC/range (not UserDefaults cache).
    @Published private(set) var liveChargeConfirmed: Bool = false
    /// True after a BLE climate packet with at least one real temp.
    @Published private(set) var liveClimateConfirmed: Bool = false

    /// Demo tick — RootView dial’ının SwiftUI yenilemesi için.
    @Published var demoUIEpoch: Int = 0

    // Drive
    @Published var kmh: Int = 0
    /// Kesirli hız (GPS / Tesla mph) — ses planı tamsayı km/h yuvarlamasından bağımsız
    @Published var kmhFine: Double = 0
    /// Phone GPS kesirli hız (Tesla HUD’dan bağımsız ses planı)
    @Published var gpsKmhFine: Double = 0
    /// GPS/Tesla dv/dt (km/h/s) — mikro gaz değişimi
    @Published var accelKmhS: Double = 0
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

    /// App rotası veya araç navigasyonu (Tesla dest/kalan) aktif mi — uyarı kapısı.
    var hasActiveNavigation: Bool {
        if routeActive { return true }
        if EtubuDemoDrive.isActive { return true }
        let dest = navDestination.trimmingCharacters(in: .whitespacesAndNewlines)
        if !dest.isEmpty { return true }
        if let rem = navRemainKm, rem > 0.15 { return true }
        return false
    }

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

    // Map — Tesla LocationState leads; phone GPS fills gaps.
    @Published var latitude: Double?
    @Published var longitude: Double?
    @Published var headingDeg: Double?
    private var lastTeslaGpsAt: Date?

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
    private var speedHist: [(t: Date, v: Double)] = []
    private var lastGpsSampleAt: Date?
    var lastGpsSampleFresh: Bool {
        lastGpsSampleAt.map { Date().timeIntervalSince($0) < 1.1 } ?? false
    }

    /// GPS/Tesla kesirli hız → dv/dt. 0.15 km/h adımlar dahil.
    func noteSpeedSample(_ kmh: Double, at now: Date = Date(), updateFine: Bool = true) {
        guard kmh.isFinite, kmh >= 0, kmh <= 280 else { return }
        if updateFine { kmhFine = kmh }
        speedHist.append((now, kmh))
        let cutoff = now.addingTimeInterval(-1.7)
        speedHist.removeAll { $0.t < cutoff }
        if speedHist.count > 16 {
            speedHist.removeFirst(speedHist.count - 16)
        }
        guard speedHist.count >= 2, let last = speedHist.last else { return }
        var a: Double?
        for sample in speedHist.dropLast() {
            let dt = last.t.timeIntervalSince(sample.t)
            if dt >= 0.32 && dt <= 1.35 {
                a = (last.v - sample.v) / dt
                break
            }
        }
        if a == nil, let prev = speedHist.dropLast().last {
            let dt = max(0.04, last.t.timeIntervalSince(prev.t))
            let dv = last.v - prev.v
            a = (abs(dv) >= 0.12 || dt >= 0.2) ? dv / dt : 0
        }
        let raw = a ?? 0
        let alpha = abs(raw) < 0.35 ? 0.5 : 0.38
        accelKmhS = alpha * accelKmhS + (1 - alpha) * raw
    }

    /// Bağlı değilken UI’da gösterilen şarj (canlı veya son bilinen, stale değilse).
    static let chargeStaleSeconds: TimeInterval = 6 * 3600

    var displaySocPercent: Int? {
        if source == .demo { return socPercent }
        if isLiveTesla {
            // Cache-as-live was the stuck-SoC bug: restored UserDefaults looked "live".
            return liveChargeConfirmed ? socPercent : nil
        }
        if isChargeStale { return nil }
        return socPercent
    }
    var displayRangeKm: Int? {
        if source == .demo { return rangeKm }
        if isLiveTesla {
            return liveChargeConfirmed ? rangeKm : nil
        }
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
            && (!liveChargeConfirmed
                || (tpmsFL.psi == nil && tpmsFR.psi == nil && tpmsRL.psi == nil && tpmsRR.psi == nil)
                || !liveClimateConfirmed)
    }
    var isAwaitingTPMS: Bool {
        isLiveTesla && tpmsFL.psi == nil && tpmsFR.psi == nil && tpmsRL.psi == nil && tpmsRR.psi == nil
    }
    var isAwaitingClimate: Bool {
        isLiveTesla && !liveClimateConfirmed
    }
    /// Extras poll: keep requesting until live SoC + climate + at least one tire are confirmed.
    var needsVehicleExtrasRefresh: Bool {
        !liveChargeConfirmed
            || !liveClimateConfirmed
            || (tpmsFL.psi == nil && tpmsFR.psi == nil && tpmsRL.psi == nil && tpmsRR.psi == nil)
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
        liveChargeConfirmed = true
        liveClimateConfirmed = true
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
        let hadPreDemoSoc = preDemoSoc != nil
        preDemoSoc = nil
        preDemoRangeKm = nil
        preDemoOutsideC = nil
        preDemoInsideC = nil
        preDemoClimateOn = nil
        liveChargeConfirmed = hadPreDemoSoc || (
            UserDefaults.standard.string(forKey: Self.lastSourceKey) == Self.vehicleSourceValue
            && socPercent != nil
        )
        // After demo, require a fresh extras sample before treating temps as live.
        liveClimateConfirmed = false
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
        // Don't treat disk cache as live until first BLE charge/climate packet.
        liveChargeConfirmed = false
        liveClimateConfirmed = false
    }

    /// Geçersiz drive paketinde bile bağlantı tazeliğini koru (weak/delayed flash yok).
    func touchDriveHealth() {
        guard !EtubuDemoDrive.isActive else { return }
        let now = Date()
        lastDriveAt = now
        lastUpdateAt = now
        if source != .tesla { source = .tesla }
    }

    /// Geçerli Tesla lastik psi bandı (bar→psi sonrası).
    static func sanitizeTirePsi(_ psi: Double?) -> Double? {
        guard let psi, psi.isFinite else { return nil }
        // Tipik EV lastik: ~28–48 psi; biraz tolerans.
        guard psi >= 18, psi <= 55 else { return nil }
        return psi
    }

    func applyTeslaDrive(
        kmh: Int?,
        kmhFine: Double? = nil,
        gear: String?,
        powerKw: Int?,
        odometerKm: Int?,
        navDestination: String?,
        navRemainKm: Double?,
        navEtaMinutes: Double?,
        vehicleEnergyAtArrival: Int? = nil,
        navDestLat: Double? = nil,
        navDestLng: Double? = nil
    ) {
        guard !EtubuDemoDrive.isActive else { return }

        // Missing speed packet → keep prior km/h (nil mph used to publish 0 and desync dial).
        let hasSpeed = kmh != nil
        let rawKmh = kmh.map { max(0, min(280, $0)) }

        let gearIn = (gear?.isEmpty == false) ? gear! : self.gear
        let gearU = gearIn.uppercased()
        let looksParked = gearU.hasPrefix("P") || gearU.hasPrefix("N")
        let speedForGate = rawKmh ?? self.kmh
        let movingDespiteGear = looksParked && speedForGate >= 3
        let effectiveGear = movingDespiteGear ? "D" : gearIn
        let parked = (effectiveGear.uppercased().hasPrefix("P")
            || effectiveGear.uppercased().hasPrefix("N")) && speedForGate < 3

        let gatedKmh: Int = {
            guard let rawKmh else { return self.kmh }
            if parked { return 0 }
            return rawKmh
        }()
        let fine: Double = {
            if parked { return 0 }
            if let incomingFine = kmhFine, incomingFine.isFinite { return max(0, min(280, incomingFine)) }
            return Double(gatedKmh)
        }()
        if hasSpeed {
            let gpsFresh = lastGpsSampleAt.map { Date().timeIntervalSince($0) < 1.0 } ?? false
            if !gpsFresh {
                noteSpeedSample(fine)
            } else {
                self.kmhFine = fine
            }
        }

        // Ani sıçrama (paket bozulması) — taze örnek varken >70 km/h delta’yı reddet.
        if hasSpeed,
           let lastDriveAt,
           Date().timeIntervalSince(lastDriveAt) < 2.5,
           abs(gatedKmh - self.kmh) > 70,
           self.kmh > 0 || gatedKmh > 80 {
            touchDriveHealth()
            return
        }

        let gatedPower: Int? = {
            guard let powerKw else { return self.powerKw }
            if gatedKmh == 0 { return abs(powerKw) < 8 ? 0 : powerKw }
            // 1–3 kW artık sıfırlanmaz — GPS ivmesi küçük gazı tamamlar
            if abs(powerKw) < 1 { return 0 }
            if abs(powerKw) > 800 { return self.powerKw }
            return powerKw
        }()

        let kmhChanged = hasSpeed && self.kmh != gatedKmh
        let gearChanged = self.gear != effectiveGear
        let powerChanged = self.powerKw != gatedPower
        if hasSpeed, kmhChanged { self.kmh = gatedKmh }
        if gearChanged { self.gear = effectiveGear }
        if powerChanged { self.powerKw = gatedPower }

        if gatedKmh > 0, let gatedPower {
            var hist = powerHistory
            hist.append(gatedPower)
            if hist.count > 40 { hist.removeFirst(hist.count - 40) }
            powerHistory = hist
        }
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
        // Araç nav bittiğinde sticky alanları temizle (yoksa uyarılar sonsuza açık kalır).
        if !routeActive {
            let destTrim = (navDestination ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let remainLive = (navRemainKm ?? 0) > 0.15
            if !destTrim.isEmpty {
                self.navDestination = destTrim
                if let navRemainKm, navRemainKm >= 0, navRemainKm < 20_000 {
                    self.navRemainKm = navRemainKm
                }
                if let navEtaMinutes, navEtaMinutes >= 0, navEtaMinutes < 10_000 {
                    self.navEtaMinutes = navEtaMinutes
                }
                if let navDestLat, let navDestLng,
                   navDestLat.isFinite, navDestLng.isFinite,
                   abs(navDestLat) > 0.01 || abs(navDestLng) > 0.01 {
                    routeDestLat = navDestLat
                    routeDestLng = navDestLng
                }
            } else if !remainLive {
                // Tesla paketinde hedef yok + kalan yok → araç navigasyonu kapalı.
                if !self.navDestination.isEmpty || (self.navRemainKm ?? 0) > 0 {
                    self.navDestination = ""
                    self.navRemainKm = nil
                    self.navEtaMinutes = nil
                }
            }
        }
        if let vehicleEnergyAtArrival, (0...100).contains(vehicleEnergyAtArrival) {
            energyAtArrivalPercent = vehicleEnergyAtArrival
            Task { @MainActor in EtubuEvRoutePlanner.shared.refreshFromLiveState() }
        } else {
            recomputeEnergyAtArrival()
        }
        self.source = .tesla
        let now = Date()
        lastDriveAt = now
        lastUpdateAt = now
        if hasSpeed || gear != nil || powerKw != nil {
            lastDriveValueAt = now
        }
        if kmhChanged || powerChanged || gearChanged {
            publishWidgetSnapshot()
        }
        let tripRoute = routeTo.isEmpty ? (navDestination ?? "") : routeTo
        Task { @MainActor in
            EtubuTripHistoryStore.shared.noteTelemetry(
                kmh: gatedKmh,
                gear: effectiveGear,
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
        portOpen: Bool?,
        homeLat: Double? = nil,
        homeLng: Double? = nil,
        workLat: Double? = nil,
        workLng: Double? = nil
    ) {
        guard !EtubuDemoDrive.isActive else { return }
        var gotLiveSample = false
        if let raw = soc {
            let soc = min(100, max(0, raw))
            // Apply immediately — confirmSoc debounce froze live % after first sample.
            socPercent = soc
            gotLiveSample = true
        }
        if let rangeKm, rangeKm > 0, rangeKm < 1200 {
            self.rangeKm = rangeKm
            gotLiveSample = true
        }
        if chargeKw != nil { self.chargeKw = chargeKw }
        isCharging = charging
        if let limitPercent, (50...100).contains(limitPercent) {
            chargeLimitPercent = limitPercent
        }
        if let amps { chargerAmps = amps }
        if let volts { chargerVolts = volts }
        if let minutesToFull { minutesToFullCharge = minutesToFull }
        if let portOpen { chargePortOpen = portOpen }
        if let homeLat, let homeLng, abs(homeLat) > 0.01 || abs(homeLng) > 0.01 {
            Self.storePin("home", lat: homeLat, lng: homeLng)
        }
        if let workLat, let workLng, abs(workLat) > 0.01 || abs(workLng) > 0.01 {
            Self.storePin("work", lat: workLat, lng: workLng)
        }
        if gotLiveSample {
            liveChargeConfirmed = true
            persistLastChargeSnapshot()
            lastExtrasAt = Date()
        }
        lastUpdateAt = Date()
        chargeEpoch &+= 1
        recomputeEnergyAtArrival()
        objectWillChange.send()
        if gotLiveSample { publishWidgetSnapshot() }
    }

    /// VCSEC GET_STATUS — lock / occupant only; never wipes Infotainment doors/TPMS.
    func applyVcsecStatus(locked: Bool?, userPresent: Bool?) {
        guard !EtubuDemoDrive.isActive else { return }
        if let locked { self.locked = locked }
        if let userPresent { self.userPresent = userPresent }
        lastUpdateAt = Date()
    }

    private static let homeLatKey = "etubu.tesla.home.lat"
    private static let homeLngKey = "etubu.tesla.home.lng"
    private static let workLatKey = "etubu.tesla.work.lat"
    private static let workLngKey = "etubu.tesla.work.lng"

    private static func storePin(_ kind: String, lat: Double, lng: Double) {
        let ud = UserDefaults.standard
        if kind == "home" {
            ud.set(lat, forKey: homeLatKey)
            ud.set(lng, forKey: homeLngKey)
        } else {
            ud.set(lat, forKey: workLatKey)
            ud.set(lng, forKey: workLngKey)
        }
    }

    /// TR-safe short-name fold — `"İş".lowercased()` alone breaks (İ → i̇).
    static func aliasFold(_ label: String) -> String {
        EtubuTrafikAPI.foldQuery(label)
    }

    static func isHomeWorkAlias(_ label: String) -> Bool {
        let fold = aliasFold(label)
        let aliases: Set<String> = [
            "home", "ev", "casa", "maison", "zuhause",
            "work", "is", "office", "travail", "arbeit", "oficina",
            "my home", "my work", "evim", "isim",
        ]
        return aliases.contains(fold)
    }

    static func savedPin(for label: String) -> (lat: Double, lng: Double)? {
        let fold = aliasFold(label)
        let ud = UserDefaults.standard
        let isHome = ["home", "ev", "casa", "maison", "zuhause", "my home", "evim"].contains(fold)
        let isWork = ["work", "is", "office", "travail", "arbeit", "oficina", "my work", "isim"].contains(fold)
        guard isHome || isWork else { return nil }
        let latKey = isHome ? homeLatKey : workLatKey
        let lngKey = isHome ? homeLngKey : workLngKey
        let lat = ud.double(forKey: latKey)
        let lng = ud.double(forKey: lngKey)
        guard abs(lat) > 0.01 || abs(lng) > 0.01 else { return nil }
        return (lat, lng)
    }

    static func placeFromSavedPin(label: String) -> EtubuRoutePlace? {
        guard let pin = savedPin(for: label) else { return nil }
        let fold = aliasFold(label)
        let isHome = ["home", "ev", "casa", "maison", "zuhause", "my home", "evim"].contains(fold)
        let nice = isHome ? "Ev" : "İş"
        return EtubuRoutePlace(
            label: nice,
            cityName: "",
            districtName: "",
            isMyLocation: false,
            lat: pin.lat,
            lng: pin.lng
        )
    }

    func applyTeslaClimate(outsideC: Double?, insideC: Double?, climateOn: Bool?) {
        if let outsideC { self.outsideC = outsideC }
        if let insideC { self.insideC = insideC }
        if let climateOn { self.climateOn = climateOn }
        if outsideC != nil || insideC != nil {
            liveClimateConfirmed = true
            lastExtrasAt = Date()
        }
        lastUpdateAt = Date()
        climateEpoch &+= 1
        objectWillChange.send()
    }

    func applyTeslaTPMS(fl: EtubuTireReading, fr: EtubuTireReading, rl: EtubuTireReading, rr: EtubuTireReading) {
        // Gelen psi’yi yaz; nil köşe eski iyi değeri korur (kısmi çerçeve).
        // 0.15 psi üzeri fark → güncelle (yavaş sızıntı / sıcaklık kayması).
        var changed = false
        func apply(_ next: EtubuTireReading, into keyPath: ReferenceWritableKeyPath<EtubuVehicleTelemetry, EtubuTireReading>) {
            if let psi = Self.sanitizeTirePsi(next.psi) {
                let prev = self[keyPath: keyPath]
                let psiDelta = prev.psi.map { abs($0 - psi) } ?? 99
                let low = psi / 14.5038 < 2.5
                let warn = next.warning || low
                if prev.psi == nil || psiDelta >= 0.12 || prev.warning != warn {
                    self[keyPath: keyPath] = EtubuTireReading(psi: psi, warning: warn)
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
        lastUpdateAt = Date()
        // Always bump epoch so UI knows extras poll landed (even identical psi).
        tpmsEpoch &+= 1
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

    func applyTeslaVehicleLocation(lat: Double?, lng: Double?, heading: Double?) {
        if let lat, let lng, abs(lat) > 0.01, abs(lng) > 0.01 {
            latitude = lat
            longitude = lng
            lastTeslaGpsAt = Date()
        }
        if let heading, heading >= 0 {
            headingDeg = heading
        }
    }

    func applyMapLocation(lat: Double?, lng: Double?, heading: Double?) {
        let teslaFresh = lastTeslaGpsAt.map { Date().timeIntervalSince($0) < 2.8 } ?? false
        if teslaFresh {
            if headingDeg == nil, let heading { headingDeg = heading }
            return
        }
        if let lat { latitude = lat }
        if let lng { longitude = lng }
        if let heading { headingDeg = heading }
    }

        /// Phone GPS hızı. Tesla HUD’u ezmez ama ses planı için her zaman dv/dt yazar.
    func applyGpsSpeedBridge(kmh: Double) {
        if EtubuDemoDrive.isActive { return }
        let next = max(0, kmh.isFinite ? kmh : 0)
        // Tesla bağlıyken kadranı ezme — GPS mikro-ivmeyi sese ver.
        let teslaOwnsHUD = source == .tesla
            || connectionState == .connected
            || connectionState == .reconnecting
            || connectionState == .connecting
            || connectionState == .pairing
            || connectionState == .waitingForCard
        let teslaDriveStale = lastDriveValueAt.map { Date().timeIntervalSince($0) > 3.5 } ?? true
        if next >= 0.8 {
            lastGpsSampleAt = Date()
            gpsKmhFine = next
            noteSpeedSample(next, updateFine: !teslaOwnsHUD || teslaDriveStale)
        } else if !teslaOwnsHUD {
            accelKmhS *= 0.45
            if abs(accelKmhS) < 0.08 { accelKmhS = 0 }
            kmhFine = 0
        }
        // Yedek 2: Tesla paketi donduysa GPS kadranı canlı tutar.
        if teslaOwnsHUD, teslaDriveStale, next >= 2.4 {
            self.kmh = Int(next.rounded())
            self.kmhFine = next
            lastUpdateAt = Date()
            return
        }
        if teslaOwnsHUD { return }
        if source == .obd {
            let age = lastDriveAt.map { Date().timeIntervalSince($0) } ?? (connectionFreshnessSeconds ?? 999)
            if age < 0.9 { return }
        }
        // < 2.4 km/h → park / GPS noise — HUD sıfır; ses örneği yukarıda alındı
        if next < 2.4 {
            if source == .gps || source == .none {
                if self.kmh != 0 { self.kmh = 0 }
                if source == .gps {
                    source = .gps
                    lastUpdateAt = Date()
                }
            }
            return
        }
        self.kmh = Int(next.rounded())
        self.kmhFine = next
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
        noteSpeedSample(Double(gated))
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
