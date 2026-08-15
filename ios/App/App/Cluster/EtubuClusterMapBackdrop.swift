import SwiftUI
import MapKit
import CoreLocation

/// Isolated MapKit wash — camera and annotations update from location/route
/// publishers only. Parent `EtubuClusterRootView` re-renders (speed, SoC, …)
/// do not rebuild MapKit when `Equatable` inputs are unchanged.
struct EtubuClusterMapBackdrop: View, Equatable {
    let theme: ClusterTheme
    var legalLead: CGFloat = 0
    let criticalAlertsOn: Bool
    let locationEnabled: Bool

    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.0, longitude: 35.0),
            span: MKCoordinateSpan(latitudeDelta: 8, longitudeDelta: 8)
        )
    )
    @State private var lastMapCenter: CLLocationCoordinate2D?
    @State private var lastMapRouteCount: Int = 0
    @State private var lastMapHeading: Double = 0
    @State private var routeCoords: [CLLocationCoordinate2D] = []
    @State private var pinHazards: [EtubuRouteHazard] = []
    @State private var vehicleLat: Double?
    @State private var vehicleLng: Double?
    @State private var vehicleHeading: Double?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.theme == rhs.theme
            && lhs.legalLead == rhs.legalLead
            && lhs.criticalAlertsOn == rhs.criticalAlertsOn
            && lhs.locationEnabled == rhs.locationEnabled
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Map(position: $camera, interactionModes: []) {
                if routeCoords.count >= 2 {
                    MapPolyline(coordinates: Self.decimateRoute(routeCoords, maxPoints: 180))
                        .stroke(theme.accent.opacity(0.8), lineWidth: 3)
                }
                ForEach(pinHazards) { hazard in
                    Annotation("", coordinate: hazard.coordinate) {
                        EtubuMapHazardMark(kind: hazard.kind, theme: theme, compact: true)
                    }
                }
                if locationEnabled, let lat = vehicleLat, let lng = vehicleLng {
                    Annotation("", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng)) {
                        EtubuMapVehicleMark(headingDeg: vehicleHeading)
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false))
            .colorScheme(.dark)
            .saturation(0.2)
            .contrast(1.08)
            .safeAreaPadding(.leading, legalLead)
            .allowsHitTesting(false)
            .overlay {
                Color.black.opacity(0.28).allowsHitTesting(false)
            }

            EtubuOsmAttributionChip(compact: true, theme: theme)
                .padding(8)
        }
        .onAppear { pullSnapshot(forceCamera: true) }
        .onReceive(EtubuVehicleTelemetry.shared.$latitude) { _ in pullSnapshot() }
        .onReceive(EtubuVehicleTelemetry.shared.$longitude) { _ in pullSnapshot() }
        .onReceive(EtubuVehicleTelemetry.shared.$headingDeg) { _ in pullSnapshot() }
        .onReceive(EtubuDriveWarnings.shared.$routeCoords) { _ in pullSnapshot(forceCamera: true) }
        .onReceive(EtubuDriveWarnings.shared.$remainingHazards) { _ in pullHazards() }
        .onReceive(EtubuDriveWarnings.shared.$hazards) { _ in pullHazards() }
    }

    private func pullHazards() {
        let w = EtubuDriveWarnings.shared
        let src = w.remainingHazards.isEmpty ? w.hazards : w.remainingHazards
        let cap = EtubuRuntimeProfile.isSimulator ? 8 : 16
        pinHazards = criticalAlertsOn ? Array(src.prefix(cap)) : []
    }

    private func pullSnapshot(forceCamera: Bool = false) {
        let t = EtubuVehicleTelemetry.shared
        let w = EtubuDriveWarnings.shared
        routeCoords = w.routeCoords
        vehicleLat = t.latitude
        vehicleLng = t.longitude
        vehicleHeading = t.headingDeg
        pullHazards()
        syncCamera(force: forceCamera)
    }

    private func desiredCamera() -> MapCameraPosition {
        if routeCoords.count >= 2 {
            let lats = routeCoords.map(\.latitude)
            let lngs = routeCoords.map(\.longitude)
            let minLat = lats.min() ?? 0
            let maxLat = lats.max() ?? 0
            let minLng = lngs.min() ?? 0
            let maxLng = lngs.max() ?? 0
            let center = CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLng + maxLng) / 2
            )
            let span = MKCoordinateSpan(
                latitudeDelta: max(0.04, (maxLat - minLat) * 1.35),
                longitudeDelta: max(0.04, (maxLng - minLng) * 1.35)
            )
            return .region(MKCoordinateRegion(center: center, span: span))
        }
        if let lat = vehicleLat, let lng = vehicleLng {
            return .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
            ))
        }
        return .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.0, longitude: 35.0),
            span: MKCoordinateSpan(latitudeDelta: 8, longitudeDelta: 8)
        ))
    }

    /// ~40 m / 18° heading / rota değişiminde kamera güncelle — MapKit thrash azaltır.
    private func syncCamera(force: Bool) {
        let desired = desiredCamera()
        let routeCount = routeCoords.count
        if routeCount >= 2 {
            if force || routeCount != lastMapRouteCount {
                lastMapRouteCount = routeCount
                camera = desired
                if let lat = vehicleLat, let lng = vehicleLng {
                    lastMapCenter = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                }
            }
            return
        }
        lastMapRouteCount = 0
        guard let lat = vehicleLat, let lng = vehicleLng else {
            if force { camera = desired }
            return
        }
        let next = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        let heading = vehicleHeading ?? lastMapHeading
        let movedM: Double = {
            guard let prev = lastMapCenter else { return 9999 }
            let a = CLLocation(latitude: prev.latitude, longitude: prev.longitude)
            let b = CLLocation(latitude: next.latitude, longitude: next.longitude)
            return a.distance(from: b)
        }()
        let headingDelta = abs(heading - lastMapHeading)
        if force || movedM >= 40 || headingDelta >= 18 {
            lastMapCenter = next
            lastMapHeading = heading
            camera = desired
        }
    }

    private static func decimateRoute(_ coords: [CLLocationCoordinate2D], maxPoints: Int) -> [CLLocationCoordinate2D] {
        guard coords.count > maxPoints, maxPoints > 2 else { return coords }
        let step = Double(coords.count - 1) / Double(maxPoints - 1)
        var out: [CLLocationCoordinate2D] = []
        out.reserveCapacity(maxPoints)
        for i in 0..<maxPoints {
            let idx = min(coords.count - 1, Int((Double(i) * step).rounded()))
            out.append(coords[idx])
        }
        return out
    }
}
