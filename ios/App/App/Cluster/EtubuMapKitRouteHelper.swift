import Foundation
import MapKit
import CoreLocation

/// Apple MapKit native route calculation & real-time traffic route adapter for vehicle navigation.
/// Computes turn-by-turn route polyline from vehicle telemetry destination and feeds it
/// directly to `EtubuDriveWarnings.shared.routeCoords` for 3D/2D map displays.
final class EtubuMapKitRouteHelper: ObservableObject {
    static let shared = EtubuMapKitRouteHelper()

    private var activeTask: Task<Void, Never>?
    private var lastRequestedDest: String = ""
    private var lastRequestedOrigin: CLLocationCoordinate2D?
    private var isCalculating = false

    private init() {}

    /// Triggered when vehicle navigation destination or location updates.
    @MainActor
    func syncRouteFromVehicleNavIfNeeded(force: Bool = false) {
        let telemetry = EtubuVehicleTelemetry.shared
        let dest = telemetry.navDestination.trimmingCharacters(in: .whitespacesAndNewlines)

        // If no destination and no active navigation, nothing to route
        if dest.isEmpty && telemetry.routeDestLat == nil {
            return
        }

        guard let curLat = telemetry.latitude, let curLng = telemetry.longitude,
              curLat.isFinite, curLng.isFinite,
              abs(curLat) > 0.01 || abs(curLng) > 0.01 else {
            return
        }

        let originCoord = CLLocationCoordinate2D(latitude: curLat, longitude: curLng)

        // Avoid re-querying if same destination and origin hasn't moved more than 600 meters
        if !force, dest == lastRequestedDest, let lastOrg = lastRequestedOrigin {
            let distM = EtubuTrafikAPI.haversineKm(originCoord.latitude, originCoord.longitude, lastOrg.latitude, lastOrg.longitude) * 1000.0
            if distM < 600.0 && !EtubuDriveWarnings.shared.routeCoords.isEmpty {
                return
            }
        }

        activeTask?.cancel()
        activeTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.lastRequestedDest = dest
            self.lastRequestedOrigin = originCoord
            self.isCalculating = true

            defer { self.isCalculating = false }

            do {
                // 1. Resolve destination placemark (either from coordinates or MKLocalSearch)
                let destMapItem: MKMapItem
                if let dLat = telemetry.routeDestLat, let dLng = telemetry.routeDestLng,
                   dLat.isFinite, dLng.isFinite, abs(dLat) > 0.01 || abs(dLng) > 0.01 {
                    let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: dLat, longitude: dLng))
                    destMapItem = MKMapItem(placemark: placemark)
                } else if !dest.isEmpty {
                    guard let resolvedItem = await self.resolveDestinationSearch(dest, near: originCoord) else {
                        return
                    }
                    destMapItem = resolvedItem
                } else {
                    return
                }

                // 2. Compute route via Apple MapKit MKDirections (incorporating real-time traffic)
                let request = MKDirections.Request()
                request.source = MKMapItem(placemark: MKPlacemark(coordinate: originCoord))
                request.destination = destMapItem
                request.transportType = .automobile
                request.requestsAlternateRoutes = false

                let directions = MKDirections(request: request)
                let response = try await directions.calculate()

                guard !Task.isCancelled else { return }

                if let primaryRoute = response.routes.first {
                    let pointCount = primaryRoute.polyline.pointCount
                    guard pointCount >= 2 else { return }

                    var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
                    primaryRoute.polyline.getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))

                    let validCoords = coords.filter { $0.latitude.isFinite && $0.longitude.isFinite }
                    guard validCoords.count >= 2 else { return }

                    // Apply coordinates to drive warnings for map rendering
                    EtubuDriveWarnings.shared.routeCoords = validCoords
                    telemetry.routeActive = true

                    if telemetry.capRouteRemainKm == nil || (telemetry.navRemainKm ?? 0) <= 0.1 {
                        telemetry.applyCapRouteRemain(active: true, remainKm: primaryRoute.distance / 1000.0)
                    }
                    if telemetry.navEtaMinutes == nil || (telemetry.navEtaMinutes ?? 0) <= 0.1 {
                        telemetry.navEtaMinutes = primaryRoute.expectedTravelTime / 60.0
                    }

                    // Kickstart warning monitor polling with newly formed route
                    EtubuDriveWarnings.shared.startPolling()
                }
            } catch {
                // MapKit error / cancelled - keep existing route if any
            }
        }
    }

    /// Resolves destination string via MKLocalSearch biased around vehicle coordinate
    private func resolveDestinationSearch(_ query: String, near center: CLLocationCoordinate2D) async -> MKMapItem? {
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = query
        req.region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 1.5, longitudeDelta: 1.5)
        )
        let search = MKLocalSearch(request: req)
        do {
            let res = try await search.start()
            return res.mapItems.first
        } catch {
            return nil
        }
    }
}
