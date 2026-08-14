import Foundation
import CoreLocation
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

    /// Bağcılar / İstanbul — permission denied or Tesla/sim fallback (Maestro uses real simctl GPS when authorized).
    static let simHomeLat = 41.0391
    static let simHomeLng = 28.8567

    @Published private(set) var gpsIndicator: EtubuGpsIndicator = .denied

    private lazy var manager: CLLocationManager = {
        let m = CLLocationManager()
        m.delegate = self
        m.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        // Hız köprüsü için yeterince sık; 2 m thrash yaratıyordu.
        m.distanceFilter = 8
        m.activityType = .automotiveNavigation
        m.pausesLocationUpdatesAutomatically = false
        return m
    }()
    private var started = false
    private var backgroundArmed = false
    private var simTimer: Timer?
    private var simAngle: Double = 0
    private var usingSim = false
    /// Real fix received — never override Maestro / device GPS with Bağcılar sim.
    private var receivedRealFix = false

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
            guard self.isLocationEnabled else {
                self.stop()
                self.publishIndicator(.denied)
                self.startSimIfNeeded(reason: "location-off")
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
                self.publishIndicator(.ok)
                // Simulator without Maestro location yet — soft Sim after long wait (don't race Maestro).
                self.scheduleSimulatorFallbackIfNoFix()
            case .denied, .restricted:
                self.publishIndicator(.denied)
                self.startSimIfNeeded(reason: "denied")
            @unknown default:
                self.publishIndicator(.denied)
                self.startSimIfNeeded(reason: "unknown")
            }
        }
    }

    /// Authorized but no CLLocation yet (rare) — only on Simulator, show Sim + Bağcılar after 6s.
    private func scheduleSimulatorFallbackIfNoFix() {
        guard EtubuRuntimeProfile.isSimulator else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self else { return }
            guard !self.receivedRealFix, !EtubuDemoDrive.isActive else { return }
            let auth = self.manager.authorizationStatus
            guard auth == .authorizedWhenInUse || auth == .authorizedAlways else { return }
            guard self.simTimer == nil else { return }
            self.usingSim = true
            self.publishIndicator(.sim)
            self.applySimFix(angle: self.simAngle)
            self.simTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
                guard let self else { return }
                DispatchQueue.main.async {
                    if self.receivedRealFix || EtubuDemoDrive.isActive {
                        self.stopSim()
                        if self.receivedRealFix { self.publishIndicator(.ok) }
                        return
                    }
                    self.simAngle = (self.simAngle + 8).truncatingRemainder(dividingBy: 360)
                    self.applySimFix(angle: self.simAngle)
                    self.publishIndicator(.sim)
                }
            }
            if let t = self.simTimer { RunLoop.main.add(t, forMode: .common) }
        }
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
            self.manager.startUpdatingLocation()
        }
    }

    func disableBackgroundUpdates() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.backgroundArmed = false
            self.manager.allowsBackgroundLocationUpdates = false
            self.manager.showsBackgroundLocationIndicator = false
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
            self.manager.stopUpdatingLocation()
            self.manager.stopUpdatingHeading()
            self.stopSim()
            EtubuVehicleTelemetry.shared.clearMapLocation()
        }
    }

    func setLocationEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.locationEnabledKey)
        if enabled {
            started = false
            receivedRealFix = false
            startIfNeeded()
        } else {
            stop()
            publishIndicator(.denied)
            startSimIfNeeded(reason: "location-off")
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard isLocationEnabled else {
            publishIndicator(.denied)
            startSimIfNeeded(reason: "location-off")
            return
        }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
            manager.startUpdatingHeading()
            started = true
            stopSim()
            publishIndicator(.ok)
            if backgroundArmed || EtubuVehicleTelemetry.shared.routeActive {
                enableBackgroundForRouteIfNeeded()
            }
        case .denied, .restricted:
            publishIndicator(.denied)
            startSimIfNeeded(reason: "denied")
        case .notDetermined:
            publishIndicator(.denied)
        @unknown default:
            publishIndicator(.denied)
            startSimIfNeeded(reason: "unknown")
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isLocationEnabled else { return }
        guard let loc = locations.last else { return }
        // Ignore stale / absurd accuracy while sim is intentional fallback.
        guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < 2_000 else { return }
        let lat = loc.coordinate.latitude
        let lng = loc.coordinate.longitude
        DispatchQueue.main.async {
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
            // Valid CLLocation.speed is m/s (≥ 0); ignore invalid (-1) and crawl noise.
            if loc.speed >= 0, loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < 65 {
                let gpsKmh = loc.speed * 3.6
                t.applyGpsSpeedBridge(kmh: gpsKmh)
            } else if loc.speed < 0 {
                t.applyGpsSpeedBridge(kmh: 0)
            }
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
            // Authorized but transient fail — do not Bağcılar-sim (would break Maestro Istanbul).
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                return
            }
            if status == .denied || status == .restricted {
                self.publishIndicator(.denied)
                self.startSimIfNeeded(reason: "denied")
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
            guard !self.usingSim else { return }
            EtubuVehicleTelemetry.shared.applyMapLocation(
                lat: EtubuVehicleTelemetry.shared.latitude,
                lng: EtubuVehicleTelemetry.shared.longitude,
                heading: h
            )
        }
    }

    // MARK: - Sim GPS (Bağcılar)

    private func startSimIfNeeded(reason: String) {
        // Maestro / cihaz gerçek fix aldıysa Bağcılar sim’e düşme.
        if receivedRealFix { return }
        if EtubuDemoDrive.isActive { return }
        let auth = manager.authorizationStatus
        // Only simulate when permission is missing or location toggle is off.
        // Do NOT sim merely because we are on Simulator — Maestro sets real Istanbul GPS.
        let deniedLike =
            !isLocationEnabled
            || auth == .denied
            || auth == .restricted
        guard deniedLike else { return }
        guard simTimer == nil else {
            publishIndicator(.denied)
            return
        }
        usingSim = true
        // Permission missing → red "İzin yok" while still feeding Bağcılar coords under the hood.
        publishIndicator(.denied)
        applySimFix(angle: simAngle)
        simTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                if EtubuDemoDrive.isActive || self.receivedRealFix {
                    self.stopSim()
                    return
                }
                let auth = self.manager.authorizationStatus
                if auth == .authorizedWhenInUse || auth == .authorizedAlways {
                    self.stopSim()
                    self.publishIndicator(.ok)
                    return
                }
                self.simAngle = (self.simAngle + 8).truncatingRemainder(dividingBy: 360)
                self.applySimFix(angle: self.simAngle)
            }
        }
        if let t = simTimer { RunLoop.main.add(t, forMode: .common) }
    }

    private func stopSim() {
        simTimer?.invalidate()
        simTimer = nil
        usingSim = false
    }

    private func applySimFix(angle: Double) {
        // ~180 m radius loop around Bağcılar — Overpass 150 m refetch works; stays in TR Maestro box.
        let rad = angle * .pi / 180
        let dLat = (180.0 / .pi) * (cos(rad) * 0.0016)
        let dLng = (180.0 / .pi) * (sin(rad) * 0.0016) / cos(Self.simHomeLat * .pi / 180)
        let lat = Self.simHomeLat + dLat
        let lng = Self.simHomeLng + dLng
        let heading = (angle + 90).truncatingRemainder(dividingBy: 360)
        EtubuRegion.updateFrom(lat: lat, lng: lng)
        Self.syncForceTrRouteFlag()
        let t = EtubuVehicleTelemetry.shared
        t.applyMapLocation(lat: lat, lng: lng, heading: heading)
        t.applyGpsSpeedBridge(kmh: 28)
        EtubuClusterAudioBridge.evalJS("""
        (function(){
          try {
            localStorage.setItem('etubu_last_map_location', JSON.stringify({lat:\(lat),lng:\(lng),sim:1}));
            window.__ETUBU_GPS_SIM__ = true;
          } catch(e) {}
        })();
        """)
        Task { @MainActor in
            if EtubuPremiumManager.shared.isPremium {
                EtubuDriveWarnings.shared.tickFromLocation()
            }
        }
    }

    private func publishIndicator(_ value: EtubuGpsIndicator) {
        if gpsIndicator != value {
            gpsIndicator = value
        }
    }
}
