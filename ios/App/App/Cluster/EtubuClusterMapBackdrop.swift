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
    @State private var lastMapRouteCount: Int = 0
    @State private var routeCoords: [CLLocationCoordinate2D] = []
    @State private var pinHazards: [EtubuRouteHazard] = []

    // Raw GPS / Telemetry targets
    @State private var targetLat: Double?
    @State private var targetLng: Double?
    @State private var targetHeading: Double = 0
    @State private var targetSpeedKmh: Double = 0

    // High-frequency 60 FPS interpolated continuum
    @State private var smoothLat: Double?
    @State private var smoothLng: Double?
    @State private var smoothHeading: Double = 0
    @State private var smoothSpeedKmh: Double = 0
    @State private var lastFrameTime: Date = Date()
    @State private var lastGpsFixTime: Date = Date()

    private let frameTicker = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

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
                        .stroke(theme.accent.opacity(0.85), lineWidth: theme == .map3D ? 4 : 3)
                }
                ForEach(pinHazards) { hazard in
                    Annotation("", coordinate: hazard.coordinate) {
                        EtubuMapHazardMark(kind: hazard.kind, theme: theme, compact: true)
                    }
                }
                if locationEnabled, let lat = smoothLat ?? targetLat, let lng = smoothLng ?? targetLng {
                    Annotation("", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng)) {
                        EtubuMapVehicleMark(headingDeg: smoothHeading, is3D: theme == .map3D)
                    }
                }
            }
            .mapStyle(
                theme == .map3D
                    ? .standard(elevation: .realistic, pointsOfInterest: .including([.evCharger, .parking, .publicTransport]), showsTraffic: true)
                    : .standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: true)
            )
            .colorScheme(.dark)
            .saturation(theme == .map3D ? 0.5 : 0.2)
            .contrast(theme == .map3D ? 1.15 : 1.08)
            .safeAreaPadding(.leading, legalLead)
            .allowsHitTesting(false)
            .overlay {
                Color.black.opacity(theme == .map3D ? 0.12 : 0.28).allowsHitTesting(false)
            }

            EtubuOsmAttributionChip(compact: true, theme: theme)
                .padding(8)
        }
        .onAppear {
            pullSnapshot(forceCamera: true)
            EtubuMapKitRouteHelper.shared.syncRouteFromVehicleNavIfNeeded()
        }
        .onReceive(frameTicker) { _ in tickFrame() }
        .onReceive(EtubuVehicleTelemetry.shared.$latitude) { _ in pullSnapshot() }
        .onReceive(EtubuVehicleTelemetry.shared.$longitude) { _ in pullSnapshot() }
        .onReceive(EtubuVehicleTelemetry.shared.$headingDeg) { _ in pullSnapshot() }
        .onReceive(EtubuVehicleTelemetry.shared.$navDestination) { _ in
            EtubuMapKitRouteHelper.shared.syncRouteFromVehicleNavIfNeeded()
        }
        .onReceive(EtubuVehicleTelemetry.shared.$routeDestLat) { _ in
            EtubuMapKitRouteHelper.shared.syncRouteFromVehicleNavIfNeeded()
        }
        .onReceive(EtubuDriveWarnings.shared.$routeCoords) { _ in pullSnapshot(forceCamera: true) }
        .onReceive(EtubuDriveWarnings.shared.$remainingHazards) { _ in pullHazards() }
        .onReceive(EtubuDriveWarnings.shared.$hazards) { _ in pullHazards() }
    }

    private func pullHazards() {
        let w = EtubuDriveWarnings.shared
        let src = w.remainingHazards.isEmpty ? w.hazards : w.remainingHazards
        let cap = EtubuRuntimeProfile.isSimulator ? 8 : 16
        pinHazards = criticalAlertsOn
            ? Array(src.filter { $0.kind != "charge" }.prefix(cap))
            : []
    }

    private func pullSnapshot(forceCamera: Bool = false) {
        let t = EtubuVehicleTelemetry.shared
        let w = EtubuDriveWarnings.shared
        routeCoords = w.routeCoords
        if routeCoords.isEmpty && (!t.navDestination.isEmpty || t.routeDestLat != nil) {
            EtubuMapKitRouteHelper.shared.syncRouteFromVehicleNavIfNeeded()
        }
        targetLat = t.latitude
        targetLng = t.longitude
        lastGpsFixTime = Date()
        if let h = t.headingDeg, h >= 0 { targetHeading = h }
        targetSpeedKmh = Double(t.kmhFine > 0 ? t.kmhFine : Double(t.kmh))
        pullHazards()

        if forceCamera || smoothLat == nil || smoothLng == nil {
            if let lat = targetLat, let lng = targetLng {
                smoothLat = lat
                smoothLng = lng
                smoothHeading = targetHeading
                smoothSpeedKmh = targetSpeedKmh
                lastFrameTime = Date()
                syncCameraDirect(force: true)
            }
        }
    }

    /// 60 FPS sub-second continuous dead-reckon navigation engine.
    private func tickFrame() {
        guard locationEnabled else { return }
        let now = Date()
        let dt = min(0.08, max(0.001, now.timeIntervalSince(lastFrameTime)))
        lastFrameTime = now

        guard let tLat = targetLat, let tLng = targetLng else { return }

        if smoothLat == nil || smoothLng == nil {
            smoothLat = tLat
            smoothLng = tLng
            smoothHeading = targetHeading
            smoothSpeedKmh = targetSpeedKmh
            return
        }

        var cLat = smoothLat!
        var cLng = smoothLng!

        // 1. Angular smoothing for heading (shortest arc)
        var diffAngle = (targetHeading - smoothHeading).truncatingRemainder(dividingBy: 360)
        if diffAngle > 180 { diffAngle -= 360 }
        if diffAngle < -180 { diffAngle += 360 }
        let headingRate = min(1.0, dt * 9.0)
        smoothHeading = (smoothHeading + diffAngle * headingRate).truncatingRemainder(dividingBy: 360)
        if smoothHeading < 0 { smoothHeading += 360 }

        // 2. Smooth speed response
        let speedRate = min(1.0, dt * 7.5)
        smoothSpeedKmh += (targetSpeedKmh - smoothSpeedKmh) * speedRate

        // 3. Continuous dead-reckoning advance
        if smoothSpeedKmh > 1.2 {
            let forwardM = (smoothSpeedKmh / 3.6) * dt
            let rad = smoothHeading * .pi / 180.0
            let dLat = (forwardM * cos(rad)) / 111_139.0
            let dLng = (forwardM * sin(rad)) / (111_139.0 * max(0.2, cos(cLat * .pi / 180.0)))
            cLat += dLat
            cLng += dLng
        }

        // 4. Smoothly pull toward latency-compensated GPS target (eliminates 10m lag)
        let fixAge = max(0, now.timeIntervalSince(lastGpsFixTime))
        let lagM = (smoothSpeedKmh / 3.6) * min(1.2, fixAge)
        let rad = smoothHeading * .pi / 180.0
        let trueTargetLat = tLat + (lagM * cos(rad)) / 111_139.0
        let trueTargetLng = tLng + (lagM * sin(rad)) / (111_139.0 * max(0.2, cos(tLat * .pi / 180.0)))

        let posLerp = min(1.0, dt * 4.5)
        cLat += (trueTargetLat - cLat) * posLerp
        cLng += (trueTargetLng - cLng) * posLerp

        smoothLat = cLat
        smoothLng = cLng

        // 5. In 3D Cockpit mode, update camera position seamlessly every frame
        if theme == .map3D {
            sync3DCamera(lat: cLat, lng: cLng, heading: smoothHeading, speed: smoothSpeedKmh)
        }
    }

    private func sync3DCamera(lat: Double, lng: Double, heading: Double, speed: Double) {
        let dynamicDistance: Double = 320.0 + min(320.0, max(0.0, (speed - 20.0) * 3.0))
        let dynamicPitch: Double = 56.0 + min(6.0, max(0.0, (speed - 40.0) * 0.05))

        // Forward look-ahead offset puts navigation arrow in lower ~35% of view
        let lookAheadM: Double = dynamicDistance * 0.28
        let rad = heading * .pi / 180.0
        let dLat = (lookAheadM * cos(rad)) / 111_139.0
        let dLng = (lookAheadM * sin(rad)) / (111_139.0 * max(0.2, cos(lat * .pi / 180.0)))
        let cameraCenter = CLLocationCoordinate2D(latitude: lat + dLat, longitude: lng + dLng)

        camera = .camera(MapCamera(
            centerCoordinate: cameraCenter,
            distance: dynamicDistance,
            heading: heading,
            pitch: dynamicPitch
        ))
    }

    private func syncCameraDirect(force: Bool) {
        if theme == .map3D {
            if let lat = smoothLat ?? targetLat, let lng = smoothLng ?? targetLng {
                sync3DCamera(lat: lat, lng: lng, heading: smoothHeading, speed: smoothSpeedKmh)
            }
            return
        }

        let routeCount = routeCoords.count
        if routeCount >= 2 {
            if force || routeCount != lastMapRouteCount {
                lastMapRouteCount = routeCount
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
                camera = .region(MKCoordinateRegion(center: center, span: span))
            }
            return
        }

        if let lat = smoothLat ?? targetLat, let lng = smoothLng ?? targetLng {
            let center = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            camera = .region(MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
            ))
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
