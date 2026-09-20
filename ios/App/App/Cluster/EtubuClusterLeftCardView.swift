import SwiftUI

enum LeftCardPage: Int, CaseIterable, Identifiable {
    case tpms, telemetry, trip, media

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .tpms: return EtubuClusterL10n.tpms
        case .telemetry: return EtubuClusterL10n.telemetry
        case .trip: return EtubuClusterL10n.trip
        case .media: return EtubuClusterL10n.media
        }
    }
}

struct EtubuClusterLeftCardView: View {
    let theme: ClusterTheme
    let layout: EtubuClusterLayoutMetrics

    @AppStorage("etubu.cluster.leftCard") private var storedLeftCardRaw: Int = LeftCardPage.tpms.rawValue
    private var leftCardPage: LeftCardPage {
        get { LeftCardPage(rawValue: storedLeftCardRaw) ?? .tpms }
        set { storedLeftCardRaw = newValue.rawValue }
    }

    @ObservedObject private var telemetry = EtubuVehicleTelemetry.shared
    @ObservedObject private var warnings = EtubuDriveWarnings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(leftCardPage.title)
                .font(EtubuClusterFonts.ui(10, weight: .heavy))
                .tracking(0.4)
                .foregroundStyle(theme.mutedText)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .allowsTightening(true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Group {
                switch leftCardPage {
                case .tpms:
                    EtubuTPMSGridView(
                        telemetry: telemetry,
                        noseUp: true,
                        compact: layout.isCompactWidth || layout.isCompactHeight,
                        maxWidth: layout.tpmsMaxW,
                        maxHeight: layout.tpmsMaxH
                    )
                case .telemetry:
                    VStack(alignment: .leading, spacing: 8) {
                        EtubuChargeDetailChip(telemetry: telemetry)
                        panelValueRow(telemetry.powerKw.map { "\($0) kW" } ?? "—")
                        panelValueRow({
                            if telemetry.isAwaitingClimate {
                                return EtubuClusterL10n.t("awaitingClimate")
                            }
                            let out = telemetry.outsideC.map { String(format: "%.0f°", $0) } ?? "—"
                            let inn = telemetry.insideC.map { String(format: "%.0f°", $0) } ?? "—"
                            return "\(out) / \(inn)"
                        }())
                        EtubuClosuresChip(telemetry: telemetry)
                    }
                case .trip:
                    VStack(alignment: .leading, spacing: 8) {
                        panelValueRow(telemetry.navRemainKm != nil ? telemetry.navRemainLabel : "—")
                        panelValueRow("\(warnings.corridorAvgKmh) km/h")
                        panelValueRow(telemetry.odometerKm.map { "\($0) km" } ?? "—")
                        EtubuPowerRegenBarView(powerKw: telemetry.powerKw, compact: true, theme: theme)
                    }
                case .media:
                    VStack(alignment: .leading, spacing: 8) {
                        EtubuMediaNowPlayingView(telemetry: telemetry)
                    }
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
                cycleLeftCard(next: true)
            }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(EtubuClusterL10n.swipeCards)
        .animation(.easeInOut(duration: 0.22), value: leftCardPage)
    }

    private func cycleLeftCard(next: Bool) {
        let all = LeftCardPage.allCases
        guard let idx = all.firstIndex(of: leftCardPage) else { return }
        let n = next ? (idx + 1) % all.count : (idx - 1 + all.count) % all.count
        storedLeftCardRaw = all[n].rawValue
    }

    private func panelValueRow(_ value: String) -> some View {
        Text(value)
            .font(EtubuClusterFonts.ui(14, weight: .semibold))
            .foregroundStyle(theme.primaryText.opacity(0.9))
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .allowsTightening(true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
