import Foundation
import CoreLocation
import Combine

/// Phone GPS for **road warnings + OSM speed limit only**.
/// Independent of Tesla `LocationState` / HUD SpeedFusion — those stay on
/// `EtubuMapLocationHelper` + `EtubuVehicleTelemetry`.
///
/// Low-lag design: single ingest stream, light jitter filter, dead-reckon from
/// `CLLocation.timestamp` so hazard distances match the car’s true position
/// (heavy EMA previously lagged ~30–50 m at highway speeds).
@MainActor
final class EtubuRoadFix: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    static let shared = EtubuRoadFix()

    @Published private(set) var latitude: Double?
    @Published private(set) var longitude: Double?
    @Published private(set) var headingDeg: Double?
    @Published private(set) var speedKmh: Double?
    @Published private(set) var accuracyM: Double?
    @Published private(set) var updatedAt: Date?

    /// Hardware sample time — prediction must use this, not wall-clock publish time.
    private var sampleTimestamp: Date?
    private var started = false
    private var lastRaw: CLLocation?

    /// Heading-only manager — position comes from `EtubuMapLocationHelper.ingest`
    /// so warnings and HUD share one GPS stream (no dual-manager fight).
    private lazy var headingManager: CLLocationManager = {
        let m = CLLocationManager()
        m.delegate = self
        m.headingFilter = 2
        return m
    }()

    private override init() {
        super.init()
    }

    func startIfNeeded() {
        guard EtubuLegalGate.shared.accepted else { return }
        guard EtubuMapLocationHelper.shared.isLocationEnabled else { return }
        if started { return }
        started = true
        switch headingManager.authorizationStatus {
        case .notDetermined:
            headingManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            headingManager.startUpdatingHeading()
        default:
            started = false
        }
    }

    func stop() {
        started = false
        headingManager.stopUpdatingHeading()
    }

    /// Dead-reckon from the last filtered fix to *now* using sample age + speed.
    /// Keeps hazard approach distances aligned with the car without any lag or offset.
    var predictedCoordinate: (lat: Double, lng: Double)? {
        guard let lat = latitude, let lng = longitude else { return nil }
        let stamp = sampleTimestamp ?? updatedAt
        let age = stamp.map { max(0, Date().timeIntervalSince($0)) } ?? 0
        guard age > 0.04, age < 3.0,
              let speed = speedKmh, speed >= 4,
              let heading = headingDeg, heading >= 0 else {
            return (lat, lng)
        }
        // Exact hardware timestamp projection (eliminates 20m lag at highway speeds)
        let distM = min(140, (speed / 3.6) * age * 1.0)
        guard distM >= 0.4 else { return (lat, lng) }
        let rad = heading * .pi / 180
        let metersPerLat = 111_139.0
        let metersPerLng = 111_139.0 * max(0.2, cos(lat * .pi / 180.0))
        let dLat = (distM * cos(rad)) / metersPerLat
        let dLng = (distM * sin(rad)) / metersPerLng
        return (lat + dLat, lng + dLng)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if EtubuLegalGate.shared.accepted {
                started = true
                headingManager.startUpdatingHeading()
            }
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Position is ingested from MapLocationHelper — ignore stray location callbacks.
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let h = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        guard h >= 0 else { return }
        if speedKmh ?? 0 < 3 { return }
        // Prefer course-from-GPS when moving; compass fills gaps.
        if let last = lastRaw, last.course >= 0, (speedKmh ?? 0) >= 8 { return }
        headingDeg = h
    }

    /// Accept a hardware sample from MapLocationHelper and filter it with low lag.
    func ingest(_ loc: CLLocation) {
        guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < 40 else { return }
        if let last = lastRaw {
            // Never rewind in time.
            if loc.timestamp <= last.timestamp { return }
            if loc.timestamp.timeIntervalSince(last.timestamp) < 0.04 { return }
            // Worse accuracy only if much newer.
            if loc.horizontalAccuracy > last.horizontalAccuracy + 10,
               loc.timestamp.timeIntervalSince(last.timestamp) < 0.7 {
                return
            }
        }
        lastRaw = loc

        var lat = loc.coordinate.latitude
        var lng = loc.coordinate.longitude
        let gpsSpeedKmh = loc.speed >= 0 ? loc.speed * 3.6 : (speedKmh ?? 0)

        if let pLat = latitude, let pLng = longitude, let prev = sampleTimestamp {
            let dt = loc.timestamp.timeIntervalSince(prev)
            if dt > 0, dt < 2.2 {
                let jumpM = CLLocation(latitude: pLat, longitude: pLng)
                    .distance(from: CLLocation(latitude: lat, longitude: lng))
                if jumpM < 140 {
                    // Moving: track GPS hard (was max α=0.55 → ~30–50 m highway lag).
                    // Crawl: mild damp of multipath jitter only.
                    let a: Double
                    if gpsSpeedKmh >= 10 || jumpM > 3.5 {
                        a = min(0.94, 0.78 + dt * 0.35)
                    } else {
                        a = min(0.72, 0.42 + dt * 0.45)
                    }
                    lat = pLat + (lat - pLat) * a
                    lng = pLng + (lng - pLng) * a
                }
            }
        }

        latitude = lat
        longitude = lng
        accuracyM = loc.horizontalAccuracy
        sampleTimestamp = loc.timestamp
        updatedAt = Date()

        if loc.speed >= 0 {
            let next = loc.speed * 3.6
            if let prev = speedKmh {
                speedKmh = prev * 0.25 + next * 0.75
            } else {
                speedKmh = next
            }
        }
        if loc.course >= 0, (speedKmh ?? 0) >= 3 {
            headingDeg = loc.course
        }
    }
}
