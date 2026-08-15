import SwiftUI

/// Isolated speed dial host. Layout/theme are Equatable so parent God-View
/// invalidations skip this subtree unless chrome actually changed. Live km/h
/// is observed here — 30 Hz chase stays inside `EtubuSpeedDialView`.
struct EtubuClusterSpeedDialHost: View, Equatable {
    let compact: Bool
    let diameter: CGFloat
    var chromeDiameter: CGFloat? = nil
    let theme: ClusterTheme
    let onCycleTheme: (Bool) -> Void

    @ObservedObject private var telemetry = EtubuVehicleTelemetry.shared
    @ObservedObject private var warnings = EtubuDriveWarnings.shared
    @ObservedObject private var demo = EtubuDemoDrive.shared
    @AppStorage("etubu.demo.running") private var demoRunningUD = false
    @AppStorage("etubu.demo.kmh") private var demoKmhUD = 0
    @AppStorage("etubu.demo.gear") private var demoGearUD = "P"
    @AppStorage("etubu.demo.power") private var demoPowerUD = 0

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.compact == rhs.compact
            && lhs.diameter == rhs.diameter
            && lhs.chromeDiameter == rhs.chromeDiameter
            && lhs.theme == rhs.theme
    }

    private var dialKmh: Int {
        if warnings.demoActive { return warnings.demoKmh < 5 ? 0 : warnings.demoKmh }
        let _ = telemetry.demoUIEpoch
        if EtubuDemoDrive.isActive || demoRunningUD {
            let v = demoKmhUD
            let raw = v > 0 ? v : max(demo.displayKmh, demoKmhUD)
            return raw < 5 ? 0 : raw
        }
        let g = telemetry.gear.uppercased()
        if (g.hasPrefix("P") || g.hasPrefix("N")), telemetry.kmh < 3 { return 0 }
        return max(0, telemetry.kmh)
    }

    private var dialKmhFine: Double {
        if warnings.demoActive { return Double(dialKmh) }
        if EtubuDemoDrive.isActive || demoRunningUD { return Double(dialKmh) }
        return telemetry.kmhFine
    }

    private var dialGear: String {
        if warnings.demoActive {
            let g = warnings.demoGear
            if (g.isEmpty || g == "P"), warnings.demoKmh >= 3 { return "D" }
            return g.isEmpty ? "D" : g
        }
        let _ = telemetry.demoUIEpoch
        if EtubuDemoDrive.isActive || demoRunningUD {
            let g = demoGearUD.isEmpty ? demo.displayGear : demoGearUD
            let kmh = demoKmhUD
            if (g.isEmpty || g == "P"), kmh >= 3 { return "D" }
            return g.isEmpty ? "D" : g
        }
        let g = telemetry.gear.uppercased()
        if (g.isEmpty || g.hasPrefix("P") || g.hasPrefix("N")), telemetry.kmh >= 3 { return "D" }
        return telemetry.gear
    }

    private var dialPowerKw: Int? {
        if warnings.demoActive { return warnings.demoPowerKw }
        let _ = telemetry.demoUIEpoch
        if EtubuDemoDrive.isActive || demoRunningUD { return demoPowerUD }
        return telemetry.powerKw
    }

    var body: some View {
        EtubuSpeedDialView(
            kmh: dialKmh,
            kmhFine: dialKmhFine,
            gear: dialGear,
            theme: theme,
            compact: compact,
            diameter: diameter,
            chromeDiameter: chromeDiameter,
            powerKw: dialPowerKw,
            powerHistory: telemetry.powerHistory,
            socPercent: telemetry.displaySocPercent
        )
        .equatable()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("etubu.dial")
        .clusterHotspot(.dial)
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { v in
                    let dy = v.translation.height
                    guard abs(dy) > 36, abs(dy) > abs(v.translation.width) else { return }
                    onCycleTheme(dy < 0)
                }
        )
        .onAppear { refreshOsm() }
        .onReceive(telemetry.$kmh) { _ in refreshOsm() }
        .onReceive(telemetry.$latitude) { _ in refreshOsm() }
        .onReceive(telemetry.$longitude) { _ in refreshOsm() }
    }

    private func refreshOsm() {
        EtubuOsmSpeedLimit.shared.refreshIfNeeded(
            lat: telemetry.latitude,
            lng: telemetry.longitude,
            speedKmh: telemetry.kmh
        )
    }
}

/// Warning twin — Equatable chrome so speed ticks from the God View skip this
/// body. `EtubuDriveWarnings` still drives content from inside the child.
struct EtubuRoadWarnTwinIsolated: View, Equatable {
    let theme: ClusterTheme
    var compact: Bool = false
    var contentScale: CGFloat = 1

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.theme == rhs.theme && lhs.compact == rhs.compact && lhs.contentScale == rhs.contentScale
    }

    var body: some View {
        EtubuRoadWarnTwinView(
            warnings: EtubuDriveWarnings.shared,
            theme: theme,
            compact: compact,
            contentScale: contentScale
        )
    }
}

struct EtubuCorridorChipIsolated: View, Equatable {
    let theme: ClusterTheme
    var compact: Bool = false
    var contentScale: CGFloat = 1

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.theme == rhs.theme && lhs.compact == rhs.compact && lhs.contentScale == rhs.contentScale
    }

    var body: some View {
        EtubuCorridorChipView(
            warnings: EtubuDriveWarnings.shared,
            theme: theme,
            compact: compact,
            contentScale: contentScale
        )
    }
}
