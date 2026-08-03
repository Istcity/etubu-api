import Foundation
import CoreLocation
import Combine

/// Phone GPS for map camera when Tesla BLE location isn't exposed by swift-tesla-ble.
final class EtubuMapLocationHelper: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = EtubuMapLocationHelper()

    static let locationEnabledKey = "etubu.cluster.locationEnabled"

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
                return
            }
            guard !self.started else { return }
            self.started = true
            switch self.manager.authorizationStatus {
            case .notDetermined:
                self.manager.requestWhenInUseAuthorization()
            case .authorizedAlways, .authorizedWhenInUse:
                self.manager.startUpdatingLocation()
                self.manager.startUpdatingHeading()
            default:
                break
            }
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
            EtubuVehicleTelemetry.shared.clearMapLocation()
        }
    }

    func setLocationEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.locationEnabledKey)
        if enabled {
            started = false
            startIfNeeded()
        } else {
            stop()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard isLocationEnabled else { return }
        if manager.authorizationStatus == .authorizedWhenInUse
            || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
            manager.startUpdatingHeading()
            started = true
            if backgroundArmed || EtubuVehicleTelemetry.shared.routeActive {
                enableBackgroundForRouteIfNeeded()
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isLocationEnabled else { return }
        guard let loc = locations.last else { return }
        let lat = loc.coordinate.latitude
        let lng = loc.coordinate.longitude
        DispatchQueue.main.async {
            // Demo kendi rota koordinatlarını yazar — gerçek GPS ile ezme.
            if EtubuDemoDrive.isActive { return }
            EtubuRegion.updateFrom(lat: lat, lng: lng)
            let t = EtubuVehicleTelemetry.shared
            t.applyMapLocation(
                lat: lat,
                lng: lng,
                heading: t.headingDeg
            )
            // Valid CLLocation.speed is m/s (≥ 0); ignore invalid (-1) and crawl noise.
            if loc.speed >= 0, loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < 65 {
                let gpsKmh = Int((loc.speed * 3.6).rounded())
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
            if t.routeActive || EtubuDriveWarnings.shared.hazards.isEmpty == false {
                EtubuDriveWarnings.shared.tickFromLocation()
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard isLocationEnabled else { return }
        let h = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        guard h >= 0 else { return }
        DispatchQueue.main.async {
            EtubuVehicleTelemetry.shared.applyMapLocation(
                lat: EtubuVehicleTelemetry.shared.latitude,
                lng: EtubuVehicleTelemetry.shared.longitude,
                heading: h
            )
        }
    }
}
