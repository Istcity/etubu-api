import SwiftUI

/// Symmetrical round multi-function dial on the right side of the instrument cluster.
/// Matches the left speedometer dial in dimensions, circular outer ring, and glowing sweep/ticks.
/// Tapping anywhere on the dial smoothly cycles between Battery/Charge, Navigation, Trip, G-Force, and Eco modes.
enum RightDialMode: String, CaseIterable, Identifiable {
    case battery
    case warnings
    case trip
    case gForce
    case ecoFlow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .battery: return EtubuClusterL10n.t("batteryGauge")
        case .warnings: return EtubuClusterL10n.t("roadWarnings")
        case .trip: return EtubuClusterL10n.t("tripStats")
        case .gForce: return EtubuClusterL10n.t("gForce")
        case .ecoFlow: return EtubuClusterL10n.t("ecoEnergy")
        }
    }

    var icon: String {
        switch self {
        case .battery: return "bolt.batteryblock.fill"
        case .warnings: return "shield.lefthalf.filled"
        case .trip: return "timer"
        case .gForce: return "gyroscope"
        case .ecoFlow: return "leaf.circle.fill"
        }
    }
}

struct EtubuRightMultiDialView: View {
    let theme: ClusterTheme
    let diameter: CGFloat
    var chromeDiameter: CGFloat? = nil
    var hasActiveRoute: Bool = false
    var routeDestinationText: String = ""

    @AppStorage("etubu.cluster.rightDialMode") private var storedModeRaw: String = RightDialMode.battery.rawValue

    private var currentMode: RightDialMode {
        get {
            if storedModeRaw == "nav" { return .warnings }
            return RightDialMode(rawValue: storedModeRaw) ?? .battery
        }
        set { storedModeRaw = newValue.rawValue }
    }

    @ObservedObject private var telemetry = EtubuVehicleTelemetry.shared
    @ObservedObject private var warnings = EtubuDriveWarnings.shared
    @ObservedObject private var evPlan = EtubuEvRoutePlanner.shared
    @ObservedObject private var thermal = EtubuThermalGuard.shared

    private var outerDiameter: CGFloat {
        chromeDiameter ?? diameter
    }

    private func cycleMode() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let all = RightDialMode.allCases
        guard let idx = all.firstIndex(of: currentMode) else { return }
        let next = all[(idx + 1) % all.count]
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            storedModeRaw = next.rawValue
        }
    }

    var body: some View {
        Button {
            cycleMode()
        } label: {
            ZStack {
                // 1. Symmetrical Dial Background & Outer Ring
                dialRingChrome

                // 2. Center Content depending on Mode
                VStack(spacing: 3) {
                    // Top mode header pill
                    let headerIcon = warnings.corridorActive ? "shield.checkerboard" : currentMode.icon
                    let headerTitle = warnings.corridorActive ? EtubuClusterL10n.t("warnKindCorridor") : currentMode.title
                    HStack(spacing: 3) {
                        Image(systemName: headerIcon)
                            .font(EtubuClusterFonts.ui(max(7, outerDiameter * 0.046), weight: .bold))
                            .foregroundStyle(warnings.corridorActive ? Color.yellow : theme.accent)

                        Text(headerTitle)
                            .font(EtubuClusterFonts.ui(max(7, outerDiameter * 0.046), weight: .bold))
                            .tracking(0.3)
                            .foregroundStyle(theme.primaryText.opacity(0.90))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                Capsule()
                                    .stroke((warnings.corridorActive ? Color.yellow : Color.white).opacity(0.18), lineWidth: 0.5)
                            )
                    )
                    .padding(.top, max(2, outerDiameter * 0.02))

                    Spacer(minLength: 0)

                    // Dynamic Mode View
                    switch currentMode {
                    case .battery:
                        batteryDialContent
                    case .warnings:
                        warningsDialContent
                    case .trip:
                        tripDialContent
                    case .gForce:
                        gForceDialContent
                    case .ecoFlow:
                        ecoFlowDialContent
                    }

                    Spacer(minLength: 0)

                    // Bottom page dots
                    HStack(spacing: 4) {
                        ForEach(RightDialMode.allCases) { m in
                            Circle()
                                .fill(m == currentMode ? theme.accent : Color.white.opacity(0.20))
                                .frame(width: m == currentMode ? 4 : 2.5, height: m == currentMode ? 4 : 2.5)
                        }
                    }
                    .padding(.bottom, max(2, outerDiameter * 0.02))
                }
                .frame(width: outerDiameter * 0.74, height: outerDiameter * 0.74)
            }
            .frame(width: outerDiameter, height: outerDiameter)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("etubu.dial.rightMulti")
        .onChange(of: warnings.corridorActive) { _, active in
            if active {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    storedModeRaw = RightDialMode.warnings.rawValue
                }
            }
        }
    }

    // MARK: - Symmetrical Dial Bezel & Gauge Ring

    private var dialRingChrome: some View {
        ZStack {
            // Semi-transparent Bezel Circle
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            theme.surface.opacity(0.70),
                            Color.black.opacity(0.40)
                        ],
                        center: .center,
                        startRadius: outerDiameter * 0.1,
                        endRadius: outerDiameter * 0.5
                    )
                )
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    theme.accent.opacity(0.50),
                                    theme.stroke.opacity(0.65),
                                    Color.white.opacity(0.18)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                )
                .shadow(color: theme.accent.opacity(0.15), radius: thermal.adaptiveShadow(6), x: 0, y: 0)

            // Outer Arc / Circular Tick Track
            Circle()
                .trim(from: 0.15, to: 0.85)
                .stroke(
                    theme.mutedText.opacity(0.20),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [4, 6])
                )
                .rotationEffect(.degrees(90))
                .frame(width: outerDiameter * 0.92, height: outerDiameter * 0.92)

            // Active Mode Circular Arc
            if currentMode == .battery {
                let soc = telemetry.displaySocPercent ?? telemetry.socPercent ?? 75
                let socFraction = Double(soc) / 100.0
                let clampedSoc = min(1.0, max(0.0, socFraction))
                let sweepLen = 0.70 * clampedSoc
                Circle()
                    .trim(from: 0.15, to: 0.15 + sweepLen)
                    .stroke(
                        batteryGradient(socFraction),
                        style: StrokeStyle(lineWidth: 4.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90))
                    .frame(width: outerDiameter * 0.92, height: outerDiameter * 0.92)
                    .shadow(color: batteryColor(socFraction).opacity(0.6), radius: 4)
            } else {
                Circle()
                    .trim(from: 0.15, to: 0.85)
                    .stroke(
                        LinearGradient(
                            colors: [theme.accent.opacity(0.2), theme.accent, theme.accent.opacity(0.3)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90))
                    .frame(width: outerDiameter * 0.92, height: outerDiameter * 0.92)
            }
        }
    }

    private func batteryColor(_ frac: Double) -> Color {
        if frac <= 0.15 { return Color(red: 1.0, green: 0.25, blue: 0.25) }
        if frac <= 0.30 { return Color(red: 1.0, green: 0.70, blue: 0.15) }
        return theme.accent
    }

    private func batteryGradient(_ frac: Double) -> LinearGradient {
        if frac <= 0.15 {
            return LinearGradient(colors: [Color.red, Color.orange], startPoint: .leading, endPoint: .trailing)
        } else if frac <= 0.30 {
            return LinearGradient(colors: [Color.orange, Color.yellow], startPoint: .leading, endPoint: .trailing)
        } else {
            return LinearGradient(colors: [theme.accent, Color.cyan], startPoint: .leading, endPoint: .trailing)
        }
    }

    // MARK: - Mode 1: Battery / Charge

    private var batteryDialContent: some View {
        let soc = telemetry.displaySocPercent ?? telemetry.socPercent ?? (warnings.demoActive ? 78 : 82)
        let rawRange = telemetry.rangeKm ?? telemetry.rangeIdealKm ?? (soc * 4)
        let isMphUnit = EtubuSpeedUnit.stored.isMph
        let displayRange = isMphUnit ? Int(Double(rawRange) * 0.621371) : rawRange
        let unitLabel = isMphUnit ? "mi" : "km"
        let pKw = telemetry.powerKw ?? (warnings.demoActive ? warnings.demoPowerKw : 0)
        let volts = telemetry.chargerVolts ?? 395
        let amps = telemetry.chargerAmps ?? (pKw > 0 ? Int(Double(pKw * 1000) / 395.0) : 0)

        return VStack(spacing: 2) {
            // Big SoC %
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(soc)")
                    .font(EtubuClusterFonts.ui(max(26, outerDiameter * 0.24), weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(theme.primaryText)
                    .shadow(color: theme.accent.opacity(0.3), radius: 4)

                Text("%")
                    .font(EtubuClusterFonts.ui(max(13, outerDiameter * 0.11), weight: .bold))
                    .foregroundStyle(theme.accent)
            }

            // Remaining Range
            HStack(spacing: 3) {
                Image(systemName: "gauge.with.dots.needle.50percent")
                    .font(EtubuClusterFonts.ui(max(9, outerDiameter * 0.06), weight: .semibold))
                    .foregroundStyle(theme.accent)

                Text("\(displayRange) \(unitLabel)")
                    .font(EtubuClusterFonts.ui(max(14, outerDiameter * 0.105), weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(theme.primaryText.opacity(0.95))
            }

            // Live Charge Power / Status
            if telemetry.isCharging {
                HStack(spacing: 3) {
                    Image(systemName: "bolt.fill")
                        .font(EtubuClusterFonts.ui(9, weight: .bold))
                        .foregroundStyle(Color.green)
                    if pKw != 0 {
                        Text("\(abs(pKw)) kW")
                            .font(EtubuClusterFonts.ui(max(10, outerDiameter * 0.075), weight: .semibold))
                            .foregroundStyle(Color.green)
                    } else {
                        Text("\(volts)V • \(amps)A")
                            .font(EtubuClusterFonts.ui(max(9, outerDiameter * 0.065), weight: .semibold))
                            .foregroundStyle(Color.green)
                    }
                }
                .padding(.top, 1)
            } else if let temp = telemetry.outsideC {
                Text(String(format: "Dış %.0f°C", temp))
                    .font(EtubuClusterFonts.ui(max(8, outerDiameter * 0.06), weight: .medium))
                    .foregroundStyle(theme.mutedText)
                    .padding(.top, 1)
            }
        }
    }

    // MARK: - Mode 2: Road Warnings & Speed Corridor

    private var warningsDialContent: some View {
        VStack(spacing: 2) {
            if warnings.corridorActive {
                // Hız Koridoru Kartı & Canlı Kuralı (Ortalama Hız, Kalan Mesafe, Hız Limiti ve Aşım)
                EtubuCorridorChipIsolated(
                    theme: theme,
                    compact: outerDiameter < 240,
                    contentScale: 0.95
                )
                .frame(maxWidth: outerDiameter * 0.88, maxHeight: outerDiameter * 0.70)
            } else if warnings.primary != nil || !warnings.remainingHazards.isEmpty {
                // Aktif Yol Uyarıları (Radar, Viraj, Tünel vb.)
                EtubuRoadWarnTwinIsolated(
                    theme: theme,
                    compact: outerDiameter < 240,
                    contentScale: 0.95
                )
                .frame(maxWidth: outerDiameter * 0.88, maxHeight: outerDiameter * 0.70)
            } else {
                // Yol Açık / Radar Tarama Aktif
                VStack(spacing: 4) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(EtubuClusterFonts.ui(max(24, outerDiameter * 0.18), weight: .semibold))
                        .foregroundStyle(theme.accent)
                        .shadow(color: theme.accent.opacity(0.4), radius: 6)

                    Text(EtubuClusterL10n.t("warnNoActive"))
                        .font(EtubuClusterFonts.ui(max(11, outerDiameter * 0.08), weight: .bold))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)

                    Text(EtubuClusterL10n.t("warnScannerActive"))
                        .font(EtubuClusterFonts.ui(max(8, outerDiameter * 0.055), weight: .medium))
                        .foregroundStyle(theme.mutedText)
                }
            }
        }
    }

    // MARK: - Mode 3: Trip Stats

    private var tripDialContent: some View {
        let trip = EtubuTripHistoryStore.shared.active
        let durMin = trip?.durationMinutes ?? (warnings.demoActive ? 42 : 0)
        let hours = durMin / 60
        let mins = durMin % 60
        let timeStr = String(format: "%02d:%02d", hours, mins)
        let dist = trip?.distanceKm ?? (warnings.demoActive ? 34.2 : Double(telemetry.kmh) * 0.15)
        let avg = trip?.avgKmh ?? (warnings.demoActive ? 68.0 : Double(max(0, warnings.corridorAvgKmh)))
        let wh = trip?.whPerKm ?? 158.0

        return VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "road.lanes")
                    .font(EtubuClusterFonts.ui(9, weight: .bold))
                    .foregroundStyle(theme.accent)
                Text(String(format: "%.1f km", dist))
                    .font(EtubuClusterFonts.ui(max(14, outerDiameter * 0.105), weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(theme.primaryText)
            }

            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(EtubuClusterFonts.ui(9, weight: .semibold))
                    .foregroundStyle(theme.mutedText)
                Text(timeStr)
                    .font(EtubuClusterFonts.ui(max(12, outerDiameter * 0.085), weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(theme.secondaryText)
            }

            HStack(spacing: 6) {
                Text(String(format: "%.0f km/h", avg))
                    .font(EtubuClusterFonts.ui(max(9, outerDiameter * 0.065), weight: .bold))
                    .foregroundStyle(theme.accent)

                Text(String(format: "%.0f Wh/km", wh))
                    .font(EtubuClusterFonts.ui(max(9, outerDiameter * 0.065), weight: .medium))
                    .foregroundStyle(Color(red: 0.2, green: 0.85, blue: 0.6))
            }
        }
    }

    // MARK: - Mode 4: G-Force

    private var gForceContentAccel: Double {
        let accel = telemetry.accelKmhS
        return max(-1.2, min(1.2, accel / 35.3))
    }

    private var gForceDialContent: some View {
        let currentG = gForceContentAccel
        let peakG = max(0.45, abs(currentG) * 1.25)
        let pKw = telemetry.powerKw ?? (warnings.demoActive ? warnings.demoPowerKw : 0)

        return VStack(spacing: 2) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    .frame(width: outerDiameter * 0.34, height: outerDiameter * 0.34)

                Circle()
                    .stroke(theme.accent.opacity(0.35), lineWidth: 1)
                    .frame(width: outerDiameter * 0.20, height: outerDiameter * 0.20)

                Circle()
                    .fill(theme.accent)
                    .frame(width: 7, height: 7)
                    .offset(x: 0, y: CGFloat(-currentG * 14))
                    .shadow(color: theme.accent, radius: 3)
            }

            Text(String(format: "%.2f G", abs(currentG)))
                .font(EtubuClusterFonts.ui(max(14, outerDiameter * 0.105), weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(theme.primaryText)

            HStack(spacing: 6) {
                Text(String(format: "Peak: %.2f G", peakG))
                    .font(EtubuClusterFonts.ui(max(8, outerDiameter * 0.055), weight: .medium))
                    .foregroundStyle(theme.mutedText)

                Text("\(max(0, pKw)) kW")
                    .font(EtubuClusterFonts.ui(max(8, outerDiameter * 0.055), weight: .bold))
                    .foregroundStyle(theme.accent)
            }
        }
    }

    // MARK: - Mode 5: Eco Energy Flow

    private var ecoFlowDialContent: some View {
        let pKw = telemetry.powerKw ?? (warnings.demoActive ? warnings.demoPowerKw : 0)
        let isRegen = pKw < 0
        let ecoScore = isRegen ? 98 : max(40, 100 - abs(pKw) / 3)

        return VStack(spacing: 2) {
            Image(systemName: isRegen ? "arrow.down.left.circle.fill" : "leaf.circle.fill")
                .font(EtubuClusterFonts.ui(max(20, outerDiameter * 0.16), weight: .bold))
                .foregroundStyle(isRegen ? Color.green : theme.accent)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(abs(pKw))")
                    .font(EtubuClusterFonts.ui(max(18, outerDiameter * 0.13), weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(theme.primaryText)

                Text("kW")
                    .font(EtubuClusterFonts.ui(max(9, outerDiameter * 0.065), weight: .bold))
                    .foregroundStyle(isRegen ? Color.green : theme.accent)
            }

            Text(isRegen ? "REJENERASYON" : "EKO: \(ecoScore)/100")
                .font(EtubuClusterFonts.ui(max(8, outerDiameter * 0.055), weight: .bold))
                .foregroundStyle(isRegen ? Color.green : theme.mutedText)
        }
    }
}
