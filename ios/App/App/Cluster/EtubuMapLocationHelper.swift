import Foundation
import CoreLocation
import Combine

/// Phone GPS for map camera when Tesla BLE location isn't exposed by swift-tesla-ble.
final class EtubuMapLocationHelper: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = EtubuMapLocationHelper()

    static let locationEnabledKey = "etubu.cluster.locationEnabled"

    private let manager = CLLocationManager()
    private var started = false

    var isLocationEnabled: Bool {
        if UserDefaults.standard.object(forKey: Self.locationEnabledKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: Self.locationEnabledKey)
    }

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 5
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

    /// GPS ve heading’i durdur; navigasyon oku için konum bilgisini temizle.
    func stop() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.started = false
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
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isLocationEnabled else { return }
        guard let loc = locations.last else { return }
        let lat = loc.coordinate.latitude
        let lng = loc.coordinate.longitude
        DispatchQueue.main.async {
            EtubuVehicleTelemetry.shared.applyMapLocation(
                lat: lat,
                lng: lng,
                heading: EtubuVehicleTelemetry.shared.headingDeg
            )
            EtubuClusterAudioBridge.evalJS("""
            (function(){
              try {
                localStorage.setItem('etubu_last_map_location', JSON.stringify({lat:\(lat),lng:\(lng)}));
              } catch(e) {}
            })();
            """)
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
