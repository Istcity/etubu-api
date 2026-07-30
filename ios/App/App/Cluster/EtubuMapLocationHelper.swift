import Foundation
import CoreLocation
import Combine

/// Phone GPS for map camera when Tesla BLE location isn't exposed by swift-tesla-ble.
final class EtubuMapLocationHelper: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = EtubuMapLocationHelper()

    private let manager = CLLocationManager()
    private var started = false

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 5
    }

    func startIfNeeded() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.started else { return }
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

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse
            || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
            manager.startUpdatingHeading()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
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
