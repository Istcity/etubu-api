import SwiftUI

enum RightCardPage: String, CaseIterable, Identifiable {
    case nav
    case batteryGauge
    case driveTime
    case gForce
    case ecoFlow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nav: return EtubuClusterL10n.t("rightCard.nav")
        case .batteryGauge: return EtubuClusterL10n.t("rightCard.battery")
        case .driveTime: return EtubuClusterL10n.t("rightCard.driveTime")
        case .gForce: return EtubuClusterL10n.t("rightCard.gForce")
        case .ecoFlow: return EtubuClusterL10n.t("rightCard.ecoFlow")
        }
    }

    var icon: String {
        switch self {
        case .nav: return "location.north.circle.fill"
        case .batteryGauge: return "bolt.car.fill"
        case .driveTime: return "timer"
        case .gForce: return "gauge.with.needle.fill"
        case .ecoFlow: return "leaf.fill"
        }
    }
}

struct EtubuClusterRightCardView: View {
    let theme: ClusterTheme
    let hasActiveRouteChrome: Bool
    let routeDestinationText: String

    @AppStorage("etubu.cluster.rightCard") private var storedRightCardRaw: String = RightCardPage.nav.rawValue
    private var rightCardPage: RightCardPage {
        get { RightCardPage(rawValue: storedRightCardRaw) ?? .nav }
        set { storedRightCardRaw = newValue.rawValue }
    }

    @ObservedObject private var telemetry = EtubuVehicleTelemetry.shared
    @ObservedObject private var warnings = EtubuDriveWarnings.shared
    @ObservedObject private var evPlan = EtubuEvRoutePlanner.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: rightCardPage.icon)
                    .font(EtubuClusterFonts.ui(10, weight: .bold))
                    .foregroundStyle(theme.accent)
                Text(rightCardPage.title)
                    .font(EtubuClusterFonts.ui(10, weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(theme.primaryText.opacity(0.90))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .allowsTightening(true)
                Spacer(minLength: 0)
                // Page indicator dots
                HStack(spacing: 3) {
                    ForEach(RightCardPage.allCases) { page in
                        Circle()
                            .fill(page == rightCardPage ? theme.accent : Color.white.opacity(0.18))
                            .frame(width: 4, height: 4)
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                    )
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 2)

            Group {
                switch rightCardPage {
                case .nav:
                    navContent
                case .batteryGauge:
                    batteryGaugeContent
                case .driveTime:
                    driveTimeContent
                case .gForce:
                    gForceContent
                case .ecoFlow:
                    ecoFlowContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.22)) {
                cycleRightCard(next: true)
            }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(EtubuClusterL10n.swipeCards)
        .animation(.easeInOut(duration: 0.22), value: rightCardPage)
    }

    private func cycleRightCard(next: Bool) {
        let all = RightCardPage.allCases
        guard let idx = all.firstIndex(of: rightCardPage) else { return }
        let n = next ? (idx + 1) % all.count : (idx - 1 + all.count) % all.count
        storedRightCardRaw = all[n].rawValue
    }

    private func navRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(EtubuClusterFonts.ui(9, weight: .semibold))
                .foregroundStyle(theme.mapHudMuted)
            Text(value.isEmpty ? "—" : value)
                .font(EtubuClusterFonts.ui(14, weight: .bold))
                .foregroundStyle(theme.mapHudText)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .allowsTightening(true)
        }
        .shadow(color: .black.opacity(0.75), radius: 1.2, y: 1)
    }

    private var navContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            if hasActiveRouteChrome {
                navRow(EtubuClusterL10n.destination, value: routeDestinationText)
                EtubuArrivalWeatherIsolated(theme: theme, mapHud: true)
                    .padding(.leading, 2)
                navRow(
                    EtubuClusterL10n.arrivalTime,
                    value: telemetry.navEtaMinutes != nil ? telemetry.arrivalTimeLabel : ""
                )
                navRow(EtubuClusterL10n.distance, value: {
                    if telemetry.effectiveRemainKm != nil { return telemetry.navRemainLabel }
                    return ""
                }())
                VStack(alignment: .leading, spacing: 2) {
                    Text(EtubuClusterL10n.energyAtArrival)
                        .font(EtubuClusterFonts.ui(10, weight: .semibold))
                        .foregroundStyle(theme.mapHudMuted)
                    HStack(spacing: 6) {
                        Text(telemetry.energyAtArrivalPercent.map { "\($0)%" } ?? "—")
                            .font(EtubuClusterFonts.ui(15, weight: .bold))
                            .foregroundStyle(telemetry.needsChargeStop ? Color.orange : theme.mapHudText)
                            .accessibilityIdentifier("etubu.ev.arrivalSoc")
                        Text(String(format: EtubuClusterL10n.t("targetSocFmt"), evPlan.targetArrivalSoc))
                            .font(EtubuClusterFonts.ui(10, weight: .medium))
                            .foregroundStyle(theme.mapHudMuted)
                    }
                }
                .shadow(color: .black.opacity(0.75), radius: 1.2, y: 1)
                routeMapLinkButtons(compact: false)
            }
            EtubuClosuresChip(telemetry: telemetry)
        }
    }

    private var batteryGaugeContent: some View {
        let soc = telemetry.displaySocPercent ?? telemetry.socPercent ?? (warnings.demoActive ? 78 : 82)
        let rawRange = telemetry.rangeKm ?? telemetry.rangeIdealKm ?? (soc * 4)
        let isMphUnit = EtubuSpeedUnit.stored.isMph
        let displayRange = isMphUnit ? Int(Double(rawRange) * 0.621371) : rawRange
        let unitLabel = isMphUnit ? "mi" : "km"
        let pKw = telemetry.powerKw ?? (warnings.demoActive ? warnings.demoPowerKw : 0)
        let volts = telemetry.chargerVolts ?? 395
        let amps = telemetry.chargerAmps ?? (pKw > 0 ? Int(Double(pKw * 1000) / 395.0) : 0)

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.14), lineWidth: 3.5)
                        .frame(width: 40, height: 40)
                    Circle()
                        .trim(from: 0, to: CGFloat(max(1, min(100, soc))) / 100.0)
                        .stroke(
                            soc > 20 ? (soc > 50 ? Color.green : Color.yellow) : Color.red,
                            style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 40, height: 40)
                    Text("\(soc)%")
                        .font(EtubuClusterFonts.ui(10, weight: .heavy))
                        .foregroundStyle(theme.primaryText)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("\(displayRange) \(unitLabel)")
                        .font(EtubuClusterFonts.ui(16, weight: .heavy))
                        .foregroundStyle(theme.primaryText)
                    Text(telemetry.isCharging ? "⚡ " + EtubuClusterL10n.t("carplaySoc") : EtubuClusterL10n.rangeKm)
                        .font(EtubuClusterFonts.ui(9, weight: .medium))
                        .foregroundStyle(theme.mutedText)
                }
            }

            HStack(spacing: 4) {
                Text(pKw < 0 ? "REGEN" : "GÜÇ")
                    .font(EtubuClusterFonts.ui(9, weight: .bold))
                    .foregroundStyle(pKw < 0 ? Color.green : theme.accent)
                Spacer()
                Text("\(abs(pKw)) kW")
                    .font(EtubuClusterFonts.ui(12, weight: .bold))
                    .foregroundStyle(pKw < 0 ? Color.green : theme.primaryText)
            }
            .padding(.top, 2)

            EtubuPowerRegenBarView(powerKw: pKw, compact: true, theme: theme)

            HStack(spacing: 4) {
                Text("\(volts)V • \(amps)A")
                    .font(EtubuClusterFonts.ui(10, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                Spacer()
                if let t = telemetry.outsideC {
                    Text(String(format: "%.0f°C", t))
                        .font(EtubuClusterFonts.ui(10, weight: .semibold))
                        .foregroundStyle(theme.mutedText)
                }
            }
            .padding(.top, 2)

            EtubuClosuresChip(telemetry: telemetry)
        }
    }

    private var driveTimeContent: some View {
        let trip = EtubuTripHistoryStore.shared.active
        let durMin = trip?.durationMinutes ?? (warnings.demoActive ? 42 : 0)
        let hours = durMin / 60
        let mins = durMin % 60
        let timeStr = String(format: "%02d:%02d", hours, mins)
        let dist = trip?.distanceKm ?? (warnings.demoActive ? 34.2 : Double(telemetry.kmh) * 0.15)
        let avg = trip?.avgKmh ?? (warnings.demoActive ? 68.0 : Double(max(0, warnings.corridorAvgKmh)))
        let wh = trip?.whPerKm ?? 158.0

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .font(EtubuClusterFonts.ui(14, weight: .bold))
                    .foregroundStyle(theme.accent)
                Text(timeStr)
                    .font(EtubuClusterFonts.ui(18, weight: .heavy))
                    .foregroundStyle(theme.primaryText)
                Text("süre")
                    .font(EtubuClusterFonts.ui(9, weight: .medium))
                    .foregroundStyle(theme.mutedText)
            }

            HStack(spacing: 4) {
                Text(EtubuClusterL10n.distance)
                    .font(EtubuClusterFonts.ui(10, weight: .medium))
                    .foregroundStyle(theme.mutedText)
                Spacer()
                Text(String(format: "%.1f km", dist))
                    .font(EtubuClusterFonts.ui(12, weight: .bold))
                    .foregroundStyle(theme.primaryText)
            }

            HStack(spacing: 4) {
                Text(EtubuClusterL10n.avgSpeed)
                    .font(EtubuClusterFonts.ui(10, weight: .medium))
                    .foregroundStyle(theme.mutedText)
                Spacer()
                Text(String(format: "%.0f km/h", avg))
                    .font(EtubuClusterFonts.ui(12, weight: .bold))
                    .foregroundStyle(theme.accent)
            }

            HStack(spacing: 4) {
                Text("Tüketim")
                    .font(EtubuClusterFonts.ui(10, weight: .medium))
                    .foregroundStyle(theme.mutedText)
                Spacer()
                Text(String(format: "%.0f Wh/km", wh))
                    .font(EtubuClusterFonts.ui(12, weight: .bold))
                    .foregroundStyle(Color(red: 0.2, green: 0.85, blue: 0.6))
            }

            EtubuClosuresChip(telemetry: telemetry)
        }
    }

    private var gForceContent: some View {
        let accel = telemetry.accelKmhS
        let currentG = max(-1.2, min(1.2, accel / 35.3))
        let peakG = max(0.45, abs(currentG) * 1.25)
        let pKw = telemetry.powerKw ?? (warnings.demoActive ? warnings.demoPowerKw : 0)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        .frame(width: 42, height: 42)
                    Circle()
                        .stroke(theme.accent.opacity(0.3), lineWidth: 1)
                        .frame(width: 24, height: 24)
                    Path { p in
                        p.move(to: CGPoint(x: 21, y: 0))
                        p.addLine(to: CGPoint(x: 21, y: 42))
                        p.move(to: CGPoint(x: 0, y: 21))
                        p.addLine(to: CGPoint(x: 42, y: 21))
                    }
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                    .frame(width: 42, height: 42)

                    Circle()
                        .fill(theme.accent)
                        .frame(width: 6, height: 6)
                        .offset(x: 0, y: CGFloat(-currentG * 15))
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 1) {
                    Text(String(format: "%.2f G", abs(currentG)))
                        .font(EtubuClusterFonts.ui(16, weight: .heavy))
                        .foregroundStyle(theme.primaryText)
                    Text(String(format: "Peak: %.2f G", peakG))
                        .font(EtubuClusterFonts.ui(9, weight: .medium))
                        .foregroundStyle(theme.mutedText)
                }
            }

            HStack(spacing: 4) {
                Text("APEX GÜÇ")
                    .font(EtubuClusterFonts.ui(9, weight: .bold))
                    .foregroundStyle(theme.accent)
                Spacer()
                Text("\(max(0, pKw)) kW")
                    .font(EtubuClusterFonts.ui(12, weight: .bold))
                    .foregroundStyle(theme.primaryText)
            }

            EtubuPowerRegenBarView(powerKw: pKw, compact: true, theme: theme)
            EtubuClosuresChip(telemetry: telemetry)
        }
    }

    private var ecoFlowContent: some View {
        let pKw = telemetry.powerKw ?? (warnings.demoActive ? warnings.demoPowerKw : 0)
        let isRegen = pKw < 0
        let ecoScore = isRegen ? 98 : max(40, 100 - abs(pKw) / 3)

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "leaf.fill")
                    .font(EtubuClusterFonts.ui(14, weight: .bold))
                    .foregroundStyle(Color.green)
                Text("\(ecoScore)")
                    .font(EtubuClusterFonts.ui(18, weight: .heavy))
                    .foregroundStyle(Color.green)
                Text("/ 100 Eko")
                    .font(EtubuClusterFonts.ui(9, weight: .medium))
                    .foregroundStyle(theme.mutedText)
            }

            HStack(spacing: 4) {
                Text(isRegen ? "Rejenerasyon" : "Eko Sürüş")
                    .font(EtubuClusterFonts.ui(10, weight: .semibold))
                    .foregroundStyle(isRegen ? Color.green : theme.secondaryText)
                Spacer()
                Text(isRegen ? "\(abs(pKw)) kW geri" : "\(pKw) kW")
                    .font(EtubuClusterFonts.ui(11, weight: .bold))
                    .foregroundStyle(isRegen ? Color.green : theme.primaryText)
            }

            EtubuPowerRegenBarView(powerKw: pKw, compact: true, theme: theme)
            EtubuClosuresChip(telemetry: telemetry)
        }
    }

    @ViewBuilder
    private func routeMapLinkButtons(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 5) {
            Button {
                EtubuRouteBridge.openInMaps(
                    destinationName: routeDestinationText.isEmpty ? "Etubu rota" : routeDestinationText
                )
            } label: {
                Label(EtubuClusterL10n.t("openInMaps"), systemImage: "map")
                    .font(EtubuClusterFonts.ui(compact ? 11 : 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.mapHudText)
            .shadow(color: .black.opacity(0.75), radius: 1.2, y: 1)
            .accessibilityIdentifier("etubu.route.openMaps")

            Button {
                EtubuRouteBridge.openNearestChargeInMaps()
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Label(EtubuClusterL10n.t("nearestCharge"), systemImage: "bolt.car.fill")
                        .font(EtubuClusterFonts.ui(compact ? 11 : 12, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let cap = warnings.nearestChargeCaption {
                        Text(cap)
                            .font(EtubuClusterFonts.ui(9, weight: .regular))
                            .foregroundStyle(theme.mapHudMuted)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.mapHudText)
            .shadow(color: .black.opacity(0.75), radius: 1.2, y: 1)
            .accessibilityIdentifier("etubu.route.nearestCharge")
        }
    }
}
