import CoreLocation
import Foundation

/// Complementary BLE + GPS speed blend. Does not own BLE or CoreLocation —
/// call sites feed samples; `blend` is a pure function.
enum SpeedFusion {
    static let lockKmh = 2.0
    static let freshSeconds: TimeInterval = 0.35
    static let fallbackSeconds: TimeInterval = 8.0
    static let maxHorizontalAccuracyM: CLLocationAccuracy = 20

    struct Input {
        var gear: String
        var parkedHint: Bool
        var bleKmh: Double
        var bleAge: TimeInterval
        var gpsKmh: Double
        var gpsValid: Bool
    }

    struct Output {
        var kmh: Double
        var usingGps: Bool
    }

    /// CoreLocation sample is usable for HUD fusion.
    static func isGpsSampleValid(_ location: CLLocation) -> Bool {
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= maxHorizontalAccuracyM else { return false }
        guard location.speed >= 0, location.speed.isFinite else { return false }
        return true
    }

    static func blend(_ input: Input) -> Output {
        let gear = input.gear.uppercased()
        let parked = input.parkedHint
            || gear.hasPrefix("P")
            || gear.hasPrefix("N")
        if parked || input.bleKmh < lockKmh {
            return Output(kmh: 0, usingGps: false)
        }

        let ble = max(0, input.bleKmh)
        let age = max(0, input.bleAge)
        let gps = max(0, input.gpsKmh)
        let gpsOk = input.gpsValid && gps.isFinite

        if age < freshSeconds {
            return Output(kmh: ble, usingGps: false)
        }

        if age >= fallbackSeconds {
            if gpsOk { return Output(kmh: gps, usingGps: true) }
            return Output(kmh: ble, usingGps: false)
        }

        guard gpsOk else {
            return Output(kmh: ble, usingGps: false)
        }
        let span = fallbackSeconds - freshSeconds
        let wGps = min(1, max(0, (age - freshSeconds) / span))
        let fused = ble * (1 - wGps) + gps * wGps
        return Output(kmh: fused, usingGps: wGps > 0.12)
    }
}
