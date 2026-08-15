import Foundation
import CoreLocation
import CoreMotion
import Combine

enum EtubuGpsIndicator: String {
    case ok
    case denied
    case sim

    var accessibilityId: String {
        switch self {
        case .ok: return "etubu.gps.ok"
        case .denied: return "etubu.gps.denied"
        case .sim: return "etubu.gps.sim"
        }
    }

    var label: String {
        switch self {
        case .ok: return EtubuClusterL10n.t("gpsChipOk")
        case .denied: return EtubuClusterL10n.t("gpsChipDenied")
        case .sim: return EtubuClusterL10n.t("gpsChipSim")
        }
    }
}

    /// Phone GPS for map camera when Tesla BLE location isn't exposed by swift-tesla-ble.
    final class EtubuMapLocationHelper: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = EtubuMapLocationHelper()

    static let locationEnabledKey = "etubu.cluster.locationEnabled"

    @Published private(set) var gpsIndicator: EtubuGpsIndicator = .denied

    private lazy var manager: CLLocationManager = {
        let m = CLLocationManager()
        m.delegate = self
        m.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        m.distanceFilter = kCLDistanceFilterNone
        m.activityType = .automotiveNavigation
        m.pausesLocationUpdatesAutomatically = false
        return m
    }()
    /// Second watch (web watchIdB) — extra callbacks when the primary stream hiccups.
    private lazy var backupManager: CLLocationManager = {
        let m = CLLocationManager()
        m.delegate = self
        m.desiredAccuracy = kCLLocationAccuracyBest
        m.distanceFilter = 1
        m.activityType = .automotiveNavigation
        m.pausesLocationUpdatesAutomatically = false
        return m
    }()
    private let motion = CMMotionManager()
    private var predictTimer: Timer?
    private var started = false
    private var backgroundArmed = false
    private var simTimer: Timer?
    private var usingSim = false
    /// Real fix received — never override Maestro / device GPS with Bağcılar sim.
    private var receivedRealFix = false
    /// Route sheet needs a geocode pin even without Tesla/OBD.
    private var routePickerVisible = false
    private var lastSpeedFix: CLLocation?
    private var lastIngestStamp: Date?
    private var lastPrimaryFixAt: Date?
    private var gpsFixKmh: Double = 0
    private var gpsAccelKmhS: Double = 0
    private var deriveKmh: Double = 0
    private var accelBoostKmh: Double = 0
    private var lastGpsFixAt: Date?
    private var lastPredictEmitAt: Date?
    private var smoothAx = 0.0
    private var smoothAy = 0.0
    private var smoothAz = 0.0
    private var forwardAxis: String?
    private var forwardSign: Double = 1

    var isLocationEnabled: Bool {
        if UserDefaults.standard.object(forKey: Self.locationEnabledKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: Self.locationEnabledKey)
    }

    private override init() {
        super.init()
        // Do NOT touch CLLocationManager here — creation alone can surface
        // authorization UI when background location mode is enabled.
    }

    func startIfNeeded() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard EtubuLegalGate.shared.accepted else { return }
            guard self.isLocationEnabled else {
                self.pauseUpdatesKeepingFix()
                self.publishIndicator(.denied)
                return
            }
            guard !self.started else { return }
            self.started = true
            switch self.manager.authorizationStatus {
            case .notDetermined:
                self.manager.requestWhenInUseAuthorization()
                self.publishIndicator(.denied)
            case .authorizedAlways, .authorizedWhenInUse:
                self.manager.startUpdatingLocation()
                self.manager.startUpdatingHeading()
                self.backupManager.startUpdatingLocation()
                self.startMotionIfNeeded()
                self.startPredictLoop()
                self.publishIndicator(.ok)
            case .denied, .restricted:
                self.started = false
                self.publishIndicator(.denied)
            @unknown default:
                self.started = false
                self.publishIndicator(.denied)
            }
        }
    }

    /// Phone GPS runs only with a vehicle session, an open route picker, an
    /// active route, or Maestro. Idle unpaired cluster stays still at 0 km/h.
    func syncWithVehicleSession() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.shouldRunLocationUpdates {
                self.startIfNeeded()
            } else {
                self.pauseUpdatesKeepingFix()
            }
        }
    }

    func setRoutePickerVisible(_ visible: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.routePickerVisible = visible
            self.syncWithVehicleSession()
        }
    }

    private var shouldRunLocationUpdates: Bool {
        guard EtubuLegalGate.shared.accepted else { return false }
        guard isLocationEnabled else { return false }
        if EtubuMaestroLaunch.isActive { return true }
        if routePickerVisible { return true }
        if EtubuDemoDrive.isActive { return false }
        let t = EtubuVehicleTelemetry.shared
        if t.routeActive { return true }
        if t.teslaSessionLive { return true }
        if t.source == .obd { return true }
        return false
    }

    /// Keep last pin; do not orbit or clear the map when GPS pauses.
    private func pauseUpdatesKeepingFix() {
        stopSim()
        applyStationaryGpsZero()
        guard started || backgroundArmed else { return }
        started = false
        backgroundArmed = false
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
        backupManager.allowsBackgroundLocationUpdates = false
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        backupManager.stopUpdatingLocation()
        stopMotion()
        stopPredictLoop()
    }

    /// Rota / sürüş aktifken arka planda GPS + uyarı tick.
    func enableBackgroundForRouteIfNeeded() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.isLocationEnabled else { return }
            self.startIfNeeded()
            let status = self.manager.authorizationStatus
            if status == .authorizedWhenInUse {
                // Always iste — arka plan location mode için.
                self.manager.requestAlwaysAuthorization()
            }
            guard status == .authorizedAlways || status == .authorizedWhenInUse else { return }
            self.backgroundArmed = true
            self.manager.allowsBackgroundLocationUpdates = true
            self.manager.showsBackgroundLocationIndicator = true
            self.manager.pausesLocationUpdatesAutomatically = false
            self.backupManager.allowsBackgroundLocationUpdates = true
            self.backupManager.pausesLocationUpdatesAutomatically = false
            self.manager.startUpdatingLocation()
            self.backupManager.startUpdatingLocation()
            self.startPredictLoop()
            self.startMotionIfNeeded()
        }
    }

    func disableBackgroundUpdates() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.backgroundArmed = false
            self.manager.allowsBackgroundLocationUpdates = false
            self.manager.showsBackgroundLocationIndicator = false
            self.backupManager.allowsBackgroundLocationUpdates = false
        }
    }

    /// GPS ve heading’i durdur; navigasyon oku için konum bilgisini temizle.
    func stop() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.started = false
            self.backgroundArmed = false
            self.manager.allowsBackgroundLocationUpdates = false
            self.manager.showsBackgroundLocationIndicator = false
            self.backupManager.allowsBackgroundLocationUpdates = false
            self.manager.stopUpdatingLocation()
            self.manager.stopUpdatingHeading()
            self.backupManager.stopUpdatingLocation()
            self.stopMotion()
            self.stopPredictLoop()
            self.stopSim()
            EtubuVehicleTelemetry.shared.clearMapLocation()
        }
    }

    func setLocationEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.locationEnabledKey)
        if enabled {
            started = false
            receivedRealFix = false
            syncWithVehicleSession()
        } else {
            stop()
            publishIndicator(.denied)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard isLocationEnabled, shouldRunLocationUpdates else {
            publishIndicator(.denied)
            pauseUpdatesKeepingFix()
            return
        }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
            manager.startUpdatingHeading()
            backupManager.startUpdatingLocation()
            startMotionIfNeeded()
            startPredictLoop()
            started = true
            stopSim()
            publishIndicator(.ok)
            if backgroundArmed || EtubuVehicleTelemetry.shared.routeActive {
                enableBackgroundForRouteIfNeeded()
            }
        case .denied, .restricted:
            started = false
            publishIndicator(.denied)
        case .notDetermined:
            publishIndicator(.denied)
        @unknown default:
            started = false
            publishIndicator(.denied)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isLocationEnabled else { return }
        guard let loc = locations.last else { return }
        // Ignore stale / absurd accuracy while sim is intentional fallback.
        guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < 2_000 else { return }
        let isBackup = manager === backupManager
        if isBackup, lastPrimaryFixAt.map({ Date().timeIntervalSince($0) < 0.28 }) == true {
            // Primary is live — still ingest backup if the timestamp is newer (web watchB).
            if let stamp = lastIngestStamp, loc.timestamp.timeIntervalSince(stamp) < 0.04 {
                return
            }
        }
        if !isBackup { lastPrimaryFixAt = Date() }
        if let stamp = lastIngestStamp, loc.timestamp == stamp { return }
        lastIngestStamp = loc.timestamp
        let lat = loc.coordinate.latitude
        let lng = loc.coordinate.longitude
        DispatchQueue.main.async {
            guard self.shouldRunLocationUpdates else { return }
            // Demo kendi rota koordinatlarını yazar — gerçek GPS ile ezme.
            if EtubuDemoDrive.isActive { return }
            self.receivedRealFix = true
            self.stopSim()
            self.publishIndicator(.ok)
            let hadRegion = EtubuRegion.hasKnownRegion
            let beforeTR = EtubuRegion.lastKnownInTurkey
            EtubuRegion.updateFrom(lat: lat, lng: lng)
            if !hadRegion || beforeTR != EtubuRegion.lastKnownInTurkey {
                Self.syncForceTrRouteFlag()
            }
            let t = EtubuVehicleTelemetry.shared
            let course = loc.course
            t.applyMapLocation(
                lat: lat,
                lng: lng,
                heading: course >= 0 ? course : t.headingDeg
            )
            if SpeedFusion.isGpsSampleValid(loc) {
                t.applyGpsSpeedBridge(
                    kmh: loc.speed * 3.6,
                    isPrediction: false,
                    sampleValid: true
                )
            } else {
                t.applyGpsSpeedBridge(kmh: 0, isPrediction: false, sampleValid: false)
            }
            _ = self.instantGpsKmh(from: loc)
            EtubuChargeEstimator.shared.ingestGps(loc)
            EtubuClusterAudioBridge.evalJS("""
            (function(){
              try {
                localStorage.setItem('etubu_last_map_location', JSON.stringify({lat:\(lat),lng:\(lng)}));
              } catch(e) {}
            })();
            """)
            // Timer arka planda durabilir — konum callback’inden uyarı tick.
            let premiumMoving = EtubuPremiumManager.shared.isPremium && t.kmh >= 5
            if t.routeActive
                || EtubuDriveWarnings.shared.hazards.isEmpty == false
                || premiumMoving {
                EtubuDriveWarnings.shared.tickFromLocation()
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            if self.receivedRealFix { return }
            let status = self.manager.authorizationStatus
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                return
            }
            if status == .denied || status == .restricted {
                self.publishIndicator(.denied)
            }
        }
    }

    /// Cap forceTr — GPS TR’ye girince seed/autocomplete yurt dışı kalmasın.
    private static func syncForceTrRouteFlag() {
        let forceTr = EtubuRegion.lastKnownInTurkey ? "1" : "0"
        EtubuClusterAudioBridge.evalJS("""
        (function(){
          try {
            var forceTr = '\(forceTr)';
            localStorage.setItem('etubu_force_tr_route', forceTr);
            sessionStorage.setItem('etubu_force_tr_route', forceTr);
            window.__etubuForceTrRoute = +forceTr;
          } catch (e) {}
        })();
        """)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard isLocationEnabled else { return }
        let h = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        guard h >= 0 else { return }
        DispatchQueue.main.async {
            guard self.shouldRunLocationUpdates else { return }
            guard !self.usingSim else { return }
            let t = EtubuVehicleTelemetry.shared
            guard !t.isVehicleStopped else { return }
            t.applyMapLocation(
                lat: t.latitude,
                lng: t.longitude,
                heading: h
            )
        }
    }

    private func stopSim() {
        simTimer?.invalidate()
        simTimer = nil
        usingSim = false
    }

    private func publishIndicator(_ value: EtubuGpsIndicator) {
        if gpsIndicator != value {
            gpsIndicator = value
        }
    }

    /// Instant GPS (web applyGpsReading): reported + Haversine derive, no 4-of-5 stall.
    private func instantGpsKmh(from loc: CLLocation) -> Double? {
        let age = Date().timeIntervalSince(loc.timestamp)
        guard age < 2.8 else { return nil }
        let accuracy = loc.horizontalAccuracy
        guard accuracy >= 0, accuracy < 55 else { return nil }

        var reported = loc.speed >= 0 ? loc.speed * 3.6 : 0
        if loc.speedAccuracy >= 0 {
            if loc.speedAccuracy > 6.5, loc.speed > 3 { reported *= 0.55 }
            // Junk crawl: accuracy worse than the speed itself below ~20 km/h.
            if loc.speed < 6, loc.speedAccuracy > max(1.2, loc.speed * 0.55) {
                reported = 0
            }
        }
        if loc.speed >= 0, loc.speed < 0.7 {
            reported = 0
        }
        let poorFix = accuracy > 28
        if poorFix, reported < 4.5 {
            reported *= max(0.15, 1 - (accuracy - 28) / 80)
        }

        var derived = 0.0
        if let prev = lastSpeedFix {
            let dt = loc.timestamp.timeIntervalSince(prev.timestamp)
            if dt > 0.04, dt < 6 {
                let dist = loc.distance(from: prev)
                derived = (dist / dt) * 3.6
                if derived > 220 { derived = 0 }
                if derived > 0.3 { deriveKmh = derived }
            }
        }
        lastSpeedFix = loc

        var instant = reported
        if reported < 2.5 {
            instant = 0
            deriveKmh *= 0.4
        } else if derived > 0.5 {
            instant = reported < 1 ? derived : reported * 0.55 + derived * 0.45
        }
        if reported < 2.2, derived < 2.8 {
            instant = min(instant, max(derived * 0.9, reported * 0.55))
        }
        if reported < 1.2, derived < 2.2, poorFix {
            instant = max(reported * 0.4, derived * 0.3)
        }
        if abs(reported - derived) > 12, reported < 5 {
            instant = reported
        }

        let now = loc.timestamp
        if let last = lastGpsFixAt {
            let dt = now.timeIntervalSince(last)
            if dt > 0.04, dt < 3 {
                let a = (instant - gpsFixKmh) / dt
                let alpha = abs(a) < 0.35 ? 0.5 : 0.38
                gpsAccelKmhS = alpha * gpsAccelKmhS + (1 - alpha) * a
            }
        }
        gpsFixKmh = max(0, instant)
        lastGpsFixAt = now
        if instant < 2.2 { instant = 0 }
        return min(200, max(0, instant))
    }

    private func startPredictLoop() {
        guard predictTimer == nil else { return }
        let t = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.predictStep()
        }
        RunLoop.main.add(t, forMode: .common)
        predictTimer = t
    }

    private func stopPredictLoop() {
        predictTimer?.invalidate()
        predictTimer = nil
    }

    /// Web predictStep: v + a·dt between fixes — never invents speed at rest.
    private func predictStep() {
        accelBoostKmh *= 0.7
        guard !EtubuDemoDrive.isActive else { return }
        let tel = EtubuVehicleTelemetry.shared
        if !tel.vehicleSessionLive {
            applyStationaryGpsZero()
            return
        }
        if tel.isVehicleStopped {
            applyStationaryGpsZero()
            return
        }
        if tel.teslaSessionLive {
            let g = tel.gear.uppercased()
            if (g.hasPrefix("P") || g.hasPrefix("N")), tel.kmh < 3 {
                applyStationaryGpsZero()
                return
            }
        }
        guard let last = lastGpsFixAt else { return }
        let elapsed = Date().timeIntervalSince(last)
        let v0 = max(gpsFixKmh, deriveKmh * 0.92)
        if elapsed > 1.25, accelBoostKmh < 0.5 { return }
        if v0 < 3.2 || gpsFixKmh < 2.4 {
            applyStationaryGpsZero()
            return
        }
        let predicted = max(
            0,
            v0 + gpsAccelKmhS * min(elapsed, 1.25) + accelBoostKmh * 0.5
        )
        if predicted < 2.4 {
            applyStationaryGpsZero()
            return
        }
        let now = Date()
        let changing = abs(gpsAccelKmhS) > 0.12 || abs(accelBoostKmh) > 0.35
        if let prev = lastPredictEmitAt, now.timeIntervalSince(prev) < (changing ? 0.018 : 0.032) {
            return
        }
        lastPredictEmitAt = now
        tel.applyGpsSpeedBridge(kmh: predicted, isPrediction: true)
    }

    private func applyStationaryGpsZero() {
        gpsAccelKmhS *= 0.4
        accelBoostKmh *= 0.35
        deriveKmh *= 0.4
        if gpsFixKmh < 3.2 { gpsFixKmh = 0 }
        EtubuVehicleTelemetry.shared.applyGpsSpeedBridge(kmh: 0, isPrediction: true)
    }

    private func startMotionIfNeeded() {
        guard motion.isAccelerometerAvailable else { return }
        guard !motion.isAccelerometerActive else { return }
        motion.accelerometerUpdateInterval = 1.0 / 30.0
        motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let a = data?.acceleration else { return }
            self.ingestMotion(ax: a.x, ay: a.y, az: a.z)
        }
    }

    private func stopMotion() {
        if motion.isAccelerometerActive {
            motion.stopAccelerometerUpdates()
        }
        accelBoostKmh = 0
    }

    private func ingestMotion(ax: Double, ay: Double, az: Double) {
        let blend = 0.35
        smoothAx = blend * ax + (1 - blend) * smoothAx
        smoothAy = blend * ay + (1 - blend) * smoothAy
        smoothAz = blend * az + (1 - blend) * smoothAz

        var forward = 0.0
        if let axis = forwardAxis {
            let raw = axis == "x" ? smoothAx : (axis == "y" ? smoothAy : smoothAz)
            forward = raw * forwardSign
        } else {
            let horiz = sqrt(smoothAx * smoothAx + smoothAy * smoothAy)
            forward = horiz - 0.15
        }

        if gpsAccelKmhS > 2.5, forwardAxis == nil {
            let mags = [("x", abs(smoothAx)), ("y", abs(smoothAy)), ("z", abs(smoothAz))]
                .sorted { $0.1 > $1.1 }
            if mags[0].1 >= 0.4 {
                forwardAxis = mags[0].0
                let raw = forwardAxis == "x" ? smoothAx : (forwardAxis == "y" ? smoothAy : smoothAz)
                forwardSign = raw >= 0 ? 1 : -1
            }
        }

        // Gravity leak on a parked dash must not invent speed.
        if gpsFixKmh < 8 {
            accelBoostKmh *= 0.5
            return
        }
        if forward > 0.12 {
            accelBoostKmh = min(55, accelBoostKmh * 0.4 + forward * 2.8 * 0.6)
            if gpsAccelKmhS < forward * 4 {
                gpsAccelKmhS = gpsAccelKmhS * 0.4 + forward * 2.8 * 0.6
            }
        } else if forward < -0.5 {
            accelBoostKmh *= 0.65
        }
    }
}
