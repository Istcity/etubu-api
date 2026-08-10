import Foundation
import CoreLocation
import Combine

extension Notification.Name {
    static let etubuDemoSoundArmed = Notification.Name("etubuDemoSoundArmed")
    static let etubuDemoSoundDisarmed = Notification.Name("etubuDemoSoundDisarmed")
}

/// Demo: İstanbul Küçükçekmece → İzmit (Kocaeli), hızlandırılmış gerçek rota simülasyonu.
@MainActor
final class EtubuDemoDrive: ObservableObject {
    static let shared = EtubuDemoDrive()

    /// Nonisolated mirror of `isRunning` — GPS/OBD/telemetry guards (any thread).
    nonisolated(unsafe) static var isActive = false

    private static let udRunning = "etubu.demo.running"
    private static let udKmh = "etubu.demo.kmh"
    private static let udGear = "etubu.demo.gear"
    private static let udPower = "etubu.demo.power"

    @Published private(set) var isRunning = false
    /// UI’nin doğrudan okuduğu demo değerleri (telemetry ezilse bile dial doğru kalsın).
    @Published private(set) var displayKmh: Int = 0
    @Published private(set) var displayGear: String = "P"
    @Published private(set) var displayPowerKw: Int = 0
    @Published var mirrorEnabled: Bool = UserDefaults.standard.bool(forKey: "etubu.demo.mirror") {
        didSet { UserDefaults.standard.set(mirrorEnabled, forKey: "etubu.demo.mirror") }
    }

    private func publishDisplay(kmh: Int, gear: String, power: Int) {
        displayKmh = kmh
        displayGear = gear
        displayPowerKw = power
        let ud = UserDefaults.standard
        ud.set(kmh, forKey: Self.udKmh)
        ud.set(gear, forKey: Self.udGear)
        ud.set(power, forKey: Self.udPower)
        // Yalnızca demo çalışırken aktif — stop() sonrası publishDisplay demo UI’yi yeniden açmasın.
        EtubuDriveWarnings.shared.applyDemoDrive(active: isRunning, kmh: kmh, gear: gear, power: power)
        EtubuVehicleTelemetry.shared.demoUIEpoch &+= 1
        EtubuVehicleTelemetry.shared.publishWidgetSnapshot()
    }

    private func publishRunning(_ on: Bool) {
        isRunning = on
        Self.isActive = on
        UserDefaults.standard.set(on, forKey: Self.udRunning)
        if on {
            EtubuDriveWarnings.shared.applyDemoDrive(
                active: true,
                kmh: displayKmh,
                gear: displayGear,
                power: displayPowerKw
            )
        } else {
            EtubuDriveWarnings.shared.applyDemoDrive(active: false, kmh: 0, gear: "P", power: 0)
        }
        EtubuVehicleTelemetry.shared.demoUIEpoch &+= 1
    }

    private var tickTask: Task<Void, Never>?
    private var tickTimer: Timer?
    /// 0…1 rota ilerlemesi
    private var progress: Double = 0
    private var route: [CLLocationCoordinate2D] = []
    private var segmentLimits: [Int] = []
    private var cumulativeMeters: [Double] = []
    private var totalMeters: Double = 1
    private var warnCycle = 0
    /// Hızlandırma (gerçek zamana göre)
    private let timeScale: Double = 32
    private let tickSec: Double = 0.2

    private init() {}

    func toggle() {
        if isRunning { stop() } else { start() }
    }

    func start() {
        guard !isRunning else { return }
        publishRunning(true)
        progress = 0
        warnCycle = 0
        buildKucukcekmeceToIzmitRoute()

        EtubuTeslaBleSession.shared.suspendForDemo()

        let t = EtubuVehicleTelemetry.shared
        t.connectionState = .connected
        t.source = .demo
        t.statusMessage = "Demo · Küçükçekmece → İzmit"
        t.deviceLabel = "Demo"
        t.routeActive = true
        t.routeFrom = "İstanbul / Küçükçekmece"
        t.routeTo = "İzmit / Kocaeli"
        t.navDestination = "İzmit, Kocaeli"
        t.beginDemoChargeOverlay(soc: 42, rangeKm: 180)
        t.powerHistory = []
        // İlk karede hemen hareket — UI / Maestro “D” + hız görsün.
        t.kmh = 28
        t.gear = "D"
        t.powerKw = 42
        t.powerHistory = [42]
        t.navRemainKm = max(1, totalMeters / 1000)
        t.refreshEnergyPlan()
        publishDisplay(kmh: 28, gear: "D", power: 42)
        if let first = route.first {
            t.latitude = first.latitude
            t.longitude = first.longitude
        }

        EtubuDriveWarnings.shared.routeCoords = route
        injectHazardsAlongRoute()
        EtubuRouteBridge.primeWarningAudio()
        // Cap www (AudioEngine) stub’dan çıkmış olsun — demoda EV ses şart.
        EtubuCapBridgeViewController.armWebContent()
        // EV ses + uyarı beep context — tema paketi (RevHeadz: tema = ses).
        let demoVoice = ClusterTheme.stored.driveVoiceKey
        UserDefaults.standard.set(demoVoice, forKey: "etubu.cluster.voice")
        EtubuClusterAudioBridge.startDrive(kmh: 28, gear: "D", source: "demo", powerKw: 42)
        EtubuClusterAudioBridge.setSoundEnabled(true, voice: demoVoice)
        NotificationCenter.default.post(name: .etubuDemoSoundArmed, object: nil)
        // Dururken levha yok — ilk step hareket limitini basar
        EtubuOsmSpeedLimit.shared.applyDemoLimit(50, highway: "residential")

        tickTask?.cancel()
        tickTimer?.invalidate()
        // İlk adım hemen; sonra common-mode timer (sheet scroll default runloop’u aç bırakmasın).
        step()
        // İlk uyarıyı beklemeden bas (warnCycle % 10).
        updateAheadWarning(
            remainM: totalMeters * (1 - progress),
            kmh: EtubuVehicleTelemetry.shared.kmh
        )
        let timer = Timer(timeInterval: tickSec, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRunning else { return }
                self.step()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
        tickTask = nil
    }

    func stop() {
        publishRunning(false)
        tickTask?.cancel()
        tickTask = nil
        tickTimer?.invalidate()
        tickTimer = nil
        let t = EtubuVehicleTelemetry.shared
        t.source = .none
        t.connectionState = EtubuTeslaVinStore.vin == nil ? .needsVIN : .disconnected
        t.statusMessage = ""
        t.deviceLabel = ""
        t.routeActive = false
        t.navDestination = ""
        t.routeTo = ""
        t.routeFrom = ""
        t.navRemainKm = nil
        t.capRouteRemainKm = nil
        t.energyAtArrivalPercent = nil
        t.needsChargeStop = false
        t.kmh = 0
        t.gear = "P"
        t.powerKw = 0
        t.rpm = 0
        t.powerHistory = []
        t.endDemoChargeOverlay()
        displayKmh = 0
        displayGear = "P"
        displayPowerKw = 0
        UserDefaults.standard.set(0, forKey: Self.udKmh)
        UserDefaults.standard.set("P", forKey: Self.udGear)
        UserDefaults.standard.set(0, forKey: Self.udPower)
        EtubuDriveWarnings.shared.applyDemoDrive(active: false, kmh: 0, gear: "P", power: 0)
        EtubuDriveWarnings.shared.clearCriticalAlerts()
        EtubuDriveWarnings.shared.routeCoords = []
        EtubuOsmSpeedLimit.shared.clearDemoOverride()
        // Stop engines only — do not force silent-mode (preserves mute/on preference).
        EtubuClusterAudioBridge.endDrive()
        NotificationCenter.default.post(name: .etubuDemoSoundDisarmed, object: nil)
        if #available(iOS 16.2, *) {
            Task { await EtubuLiveActivityController.end() }
        }
        EtubuTeslaBleSession.shared.resumeAfterDemo()
        EtubuVehicleTelemetry.shared.demoUIEpoch &+= 1
    }

    // MARK: - Rota: Küçükçekmece → İzmit (TEM / O-4 yaklaşık)

    private func buildKucukcekmeceToIzmitRoute() {
        // Anahtar noktalar (WGS84) — İstanbul batı → Gebze → İzmit
        let keys: [(CLLocationDegrees, CLLocationDegrees, Int)] = [
            (41.0027, 28.7780, 50),   // Küçükçekmece yerleşim
            (41.0150, 28.8050, 50),
            (41.0350, 28.8450, 70),   // TEM’e çıkış
            (41.0550, 28.9000, 90),
            (41.0700, 28.9800, 110),  // TEM hızlanma
            (41.0780, 29.0800, 120),  // Otoyol
            (41.0600, 29.2000, 120),
            (40.9800, 29.3200, 120),  // Gebze yaklaşım
            (40.8500, 29.4200, 120),  // Gebze
            (40.8020, 29.5000, 120),
            (40.7850, 29.7000, 110),  // İzmit yaklaşım
            (40.7720, 29.8500, 90),
            (40.7650, 29.9400, 50),   // İzmit merkez
        ]

        var dense: [CLLocationCoordinate2D] = []
        var limits: [Int] = []
        for i in 0..<(keys.count - 1) {
            let a = keys[i]
            let b = keys[i + 1]
            let steps = 14
            for s in 0..<steps {
                let u = Double(s) / Double(steps)
                dense.append(CLLocationCoordinate2D(
                    latitude: a.0 + (b.0 - a.0) * u,
                    longitude: a.1 + (b.1 - a.1) * u
                ))
                limits.append(a.2)
            }
        }
        if let last = keys.last {
            dense.append(CLLocationCoordinate2D(latitude: last.0, longitude: last.1))
            limits.append(last.2)
        }

        route = dense
        segmentLimits = limits
        cumulativeMeters = [0]
        var sum: Double = 0
        for i in 1..<dense.count {
            let d = Self.haversineM(dense[i - 1], dense[i])
            sum += d
            cumulativeMeters.append(sum)
        }
        totalMeters = max(1, sum)
    }

    private func step() {
        let movingLimit = currentRoadLimit()
        // Hedef hız: yol limitinin ~%92’si; kalkış/varışta yumuşat
        let edge = progress < 0.04 || progress > 0.96
        let targetKmh: Double = {
            if progress >= 1 { return 0 }
            if progress < 0.02 { return 25 } // kalkış
            if progress > 0.97 { return max(0, 40 * (1 - progress) / 0.03) }
            return Double(movingLimit) * (edge ? 0.75 : 0.92)
        }()

        let t = EtubuVehicleTelemetry.shared
        let prev = Double(t.kmh)
        let accelCap = 14.0 // km/h per tick — daha yumuşak tırmanış
        let delta = max(-18, min(accelCap, targetKmh - prev))
        let kmh = Int(max(0, (prev + delta).rounded()))
        // Motor sesi için güç: hızlanma / cruise / regen net olsun
        let accel = (Double(kmh) - prev) / max(0.05, tickSec)
        let power: Int = {
            if kmh < 3 { return 0 }
            if accel > 0.8 {
                return Int(min(260, 48 + accel * 14 + Double(kmh) * 0.4).rounded())
            }
            if accel < -1.2 {
                return Int(max(-140, accel * 9 - Double(kmh) * 0.15).rounded())
            }
            // Cruise — motora hafif yük
            return Int(max(12, 18 + Double(kmh) * 0.28).rounded())
        }()
        let gear: String = kmh < 3 ? (progress > 0.98 ? "P" : "D") : "D"

        // Mesafeyi hız × zaman × scale ile ilerle
        if kmh >= 3, progress < 1 {
            let metersPerTick = (Double(kmh) / 3.6) * tickSec * timeScale
            progress = min(1, progress + metersPerTick / totalMeters)
        } else if progress >= 1 {
            progress = 1
        }

        let idx = routeIndex(at: progress)
        let coord = interpolate(at: progress)
        let heading = headingAt(index: idx)

        t.kmh = kmh
        t.gear = gear
        t.powerKw = power
        publishDisplay(kmh: kmh, gear: gear, power: power)
        // Sparkline / regen bar — aynı history yolu (applyTeslaDrive ile uyumlu).
        var hist = t.powerHistory
        hist.append(power)
        if hist.count > 40 { hist.removeFirst(hist.count - 40) }
        t.powerHistory = hist
        t.rpm = max(0, kmh * 28)
        // Demo tick: sabit demo SoC (araç cache’ine yazılmaz).
        t.socPercent = 42
        t.rangeKm = 180
        t.routeActive = true
        if t.routeTo.isEmpty { t.routeTo = "İzmit / Kocaeli" }
        if t.navDestination.isEmpty { t.navDestination = "İzmit, Kocaeli" }
        t.latitude = coord.latitude
        t.longitude = coord.longitude
        t.headingDeg = heading
        t.lastUpdateAt = Date()
        t.source = .demo
        t.connectionState = .connected
        t.statusMessage = "Demo · Küçükçekmece → İzmit"
        t.deviceLabel = "Demo"

        let remainM = totalMeters * (1 - progress)
        t.navRemainKm = max(0, remainM / 1000)
        // ETA: kalan mesafe / anlık hız (görsel; timeScale yalnızca hareketi hızlandırır)
        if kmh > 5 {
            let hours = (remainM / 1000) / Double(kmh)
            t.navEtaMinutes = hours * 60
        } else {
            t.navEtaMinutes = nil
        }
        t.refreshEnergyPlan()
        EtubuTripHistoryStore.shared.noteTelemetry(
            kmh: kmh,
            gear: gear,
            odo: t.odometerKm,
            powerKw: power,
            routeTo: t.routeTo.isEmpty ? "İzmit" : t.routeTo
        )

        EtubuClusterAudioBridge.pushDrive(kmh: kmh, powerKw: power, source: "demo")

        // Levha: yalnızca hareket varken
        if kmh >= 5 {
            let lim = currentRoadLimit()
            let hw: String = {
                switch lim {
                case ...50: return "residential"
                case 51...90: return "primary"
                case 91...110: return "trunk"
                default: return "motorway"
                }
            }()
            EtubuOsmSpeedLimit.shared.applyDemoLimit(lim, highway: hw)
            EtubuDriveWarnings.shared.corridorLimit = lim
            EtubuDriveWarnings.shared.corridorAvgKmh = max(40, kmh - 6)
            EtubuDriveWarnings.shared.corridorOver = kmh > lim + 5
            EtubuDriveWarnings.shared.corridorActive = lim >= 90
        } else {
            EtubuOsmSpeedLimit.shared.applyDemoLimit(nil)
            EtubuDriveWarnings.shared.corridorActive = false
            EtubuDriveWarnings.shared.corridorOver = false
        }

        warnCycle += 1
        if kmh >= 5, warnCycle % 10 == 0 {
            updateAheadWarning(remainM: remainM, kmh: kmh)
        } else if kmh < 5 {
            EtubuDriveWarnings.shared.primary = nil
            EtubuDriveWarnings.shared.queue = []
        }

        if #available(iOS 16.2, *) {
            Task { await EtubuLiveActivityController.publishCurrent() }
        }

        // Rota bitti — kısa park, sonra başa sar (döngü)
        if progress >= 1, kmh < 2 {
            progress = 0
            t.statusMessage = "Demo · tekrar: Küçükçekmece → İzmit"
        }
    }

    private func currentRoadLimit() -> Int {
        let idx = min(segmentLimits.count - 1, max(0, routeIndex(at: progress)))
        return segmentLimits.isEmpty ? 90 : segmentLimits[idx]
    }

    private func routeIndex(at p: Double) -> Int {
        guard !cumulativeMeters.isEmpty else { return 0 }
        let target = p * totalMeters
        var lo = 0, hi = cumulativeMeters.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if cumulativeMeters[mid] < target { lo = mid + 1 } else { hi = mid }
        }
        return max(0, lo - 1)
    }

    private func interpolate(at p: Double) -> CLLocationCoordinate2D {
        guard route.count >= 2 else {
            return route.first ?? CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0)
        }
        let target = p * totalMeters
        let i = routeIndex(at: p)
        let j = min(i + 1, route.count - 1)
        let a = cumulativeMeters[i]
        let b = cumulativeMeters[j]
        let u = b > a ? (target - a) / (b - a) : 0
        let c0 = route[i], c1 = route[j]
        return CLLocationCoordinate2D(
            latitude: c0.latitude + (c1.latitude - c0.latitude) * u,
            longitude: c0.longitude + (c1.longitude - c0.longitude) * u
        )
    }

    private func headingAt(index: Int) -> Double {
        guard route.count >= 2 else { return 90 }
        let i = min(max(0, index), route.count - 2)
        let a = route[i], b = route[i + 1]
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        var deg = atan2(y, x) * 180 / .pi
        if deg < 0 { deg += 360 }
        return deg
    }

    private func injectHazardsAlongRoute() {
        guard route.count > 20 else { return }
        let specs: [(String, Int, Double)] = [
            ("radar", 20, 8),
            ("corridor", 35, 22),
            ("charge", 50, 40),
            ("weather", 65, 55),
            ("control", 80, 70),
            ("radar", 90, 85),
        ]
        var list: [EtubuRouteHazard] = []
        for (kind, pct, alongKm) in specs {
            let idx = min(route.count - 1, max(0, Int(Double(route.count - 1) * Double(pct) / 100)))
            let c = route[idx]
            list.append(EtubuRouteHazard(
                id: "demo-\(kind)-\(pct)",
                kind: kind,
                label: kind == "corridor" ? "TEM koridor" : (kind == "charge" ? "Gebze istasyon" : ""),
                lat: c.latitude,
                lng: c.longitude,
                maxspeed: kind == "corridor" ? 120 : (kind == "radar" ? 120 : nil),
                kw: kind == "charge" ? 180 : nil,
                routeIdx: idx,
                alongKm: alongKm,
                distanceLabel: String(format: "%.0f km", alongKm)
            ))
        }
        let w = EtubuDriveWarnings.shared
        w.hazards = list
        w.remainingHazards = list
        w.brief = EtubuRouteBriefSummary(
            radarCount: 2, controlCount: 1, corridorCount: 1, chargeCount: 1, weatherCount: 1
        )
        w.remainingBrief = w.brief
        w.corridorActive = false
        w.corridorLabel = "TEM / O-4"
        EtubuVehicleTelemetry.shared.refreshEnergyPlan()
    }

    private func updateAheadWarning(remainM: Double, kmh: Int) {
        let w = EtubuDriveWarnings.shared
        let alongNow = progress * totalMeters / 1000
        let ahead = w.hazards
            .filter { ($0.alongKm ?? 0) > alongNow + 0.2 }
            .sorted { ($0.alongKm ?? 0) < ($1.alongKm ?? 0) }
        guard let next = ahead.first, let along = next.alongKm else {
            w.primary = nil
            w.queue = []
            w.remainingHazards = []
            return
        }
        let distM = max(50, (along - alongNow) * 1000)
        let stage: EtubuWarnStage = {
            if distM <= 300 { return .critical }
            if distM <= 1000 { return .near }
            if distM <= 2000 { return .mid }
            return .far
        }()
        let distLabel: String = {
            if distM >= 5000 {
                let stepped = max(10, Int(distM / 10000) * 10)
                return "\(stepped) km"
            }
            if distM >= 2000 { return "\(max(1, Int(distM / 1000))) km" }
            if distM >= 300 { return "\(Int(distM / 100) * 100) m" }
            if distM >= 100 { return "\(Int(distM / 50) * 50) m" }
            return "\(max(10, Int(distM / 10) * 10)) m"
        }()
        let item = EtubuWarnItem(
            id: next.id,
            kind: next.kind,
            title: next.kindTitle,
            distanceLabel: distLabel,
            stage: stage,
            meta: next.label
        )
        w.primary = item
        w.queue = [item] + ahead.dropFirst().prefix(2).map { h in
            let d = max(100, ((h.alongKm ?? along) - alongNow) * 1000)
            return EtubuWarnItem(
                id: h.id,
                kind: h.kind,
                title: h.kindTitle,
                distanceLabel: d >= 1000 ? String(format: "%.0f km", d / 1000) : "\(Int(d)) m",
                stage: .far,
                meta: h.label
            )
        }
        w.remainingHazards = ahead
        EtubuVehicleTelemetry.shared.refreshEnergyPlan()
        EtubuClusterAudioBridge.playWarnCue(
            id: item.id,
            kind: item.kind,
            stage: item.stage.rawValue,
            phrase: "\(next.speakRootTR) \(distLabel)"
        )
        _ = kmh
        _ = remainM
    }

    private static func haversineM(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let r = 6_371_000.0
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let la1 = a.latitude * .pi / 180
        let la2 = b.latitude * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(la1) * cos(la2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1, sqrt(h)))
    }
}
