import SwiftUI

/// Unified central HUD information module for Dual-Dial layout.
/// Displays Left TPMS (close to left dial) and Right TPMS (close to right dial)
/// with a clean, uncluttered center spacer.
struct EtubuClusterCenterInfoModule: View {
    let theme: ClusterTheme
    let width: CGFloat
    let height: CGFloat
    var contentScale: CGFloat = 1.0
    var criticalAlertsOn: Bool = true
    var remotePinUnderWarn: Bool = false
    var tesla: EtubuTeslaBleSession? = nil

    @ObservedObject private var telemetry = EtubuVehicleTelemetry.shared
    @AppStorage("etubu.tpms.unit.bar") private var showBarUnit = false

    var body: some View {
        VStack(spacing: 3) {
            HStack(alignment: .center, spacing: 4) {
                // 1. SOL KADRANA YAKIN: Sol Lastik Bilgileri (FL / RL) - Kompakt & Kısaltmalı
                VStack(alignment: .leading, spacing: max(2, height * 0.06)) {
                    tireReadout(reading: telemetry.tpmsFL, title: EtubuClusterL10n.t("tireFLShort"), isRightSide: false)
                    tireReadout(reading: telemetry.tpmsRL, title: EtubuClusterL10n.t("tireRLShort"), isRightSide: false)
                }
                .frame(width: max(42, width * 0.18), alignment: .leading)

                // 2. ORTA: Çift kadranda orta uyarılar kaldırıldı; temiz ve ferah boşluk
                Spacer(minLength: 0)
                    .frame(maxWidth: .infinity)

                // 3. SAĞ KADRANA YAKIN: Sağ Lastik Bilgileri (FR / RR) - Kompakt & Kısaltmalı
                VStack(alignment: .trailing, spacing: max(2, height * 0.06)) {
                    tireReadout(reading: telemetry.tpmsFR, title: EtubuClusterL10n.t("tireFRShort"), isRightSide: true)
                    tireReadout(reading: telemetry.tpmsRR, title: EtubuClusterL10n.t("tireRRShort"), isRightSide: true)
                }
                .frame(width: max(42, width * 0.18), alignment: .trailing)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .onTapGesture {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.easeInOut(duration: 0.2)) {
                    showBarUnit.toggle()
                }
            }

            if remotePinUnderWarn, let tesla = tesla {
                EtubuRemotePinnedBar(width: width * 0.65, theme: theme, tesla: tesla)
            }
        }
        .frame(width: width, height: height, alignment: .center)
        .clipped()
    }

    private func tireValAndUnit(_ reading: EtubuTireReading) -> (val: String, unit: String) {
        if showBarUnit {
            if let bar = reading.bar {
                return (String(format: "%.1f", bar), "BAR")
            }
            if let psi = reading.psi {
                return (String(format: "%.1f", psi * 0.0689476), "BAR")
            }
        } else {
            if let psi = reading.psi {
                return ("\(Int(psi.rounded()))", "PSI")
            }
            if let bar = reading.bar {
                return ("\(Int((bar / 0.0689476).rounded()))", "PSI")
            }
        }
        return ("—", showBarUnit ? "BAR" : "PSI")
    }

    private func tireReadout(reading: EtubuTireReading, title: String, isRightSide: Bool) -> some View {
        let (valStr, unitStr) = tireValAndUnit(reading)
        let warn = reading.warning || (reading.psi.map { $0 < 30 || $0 > 48 } ?? false)
        let valColor = warn ? Color.orange : theme.primaryText.opacity(0.95)

        return VStack(alignment: isRightSide ? .trailing : .leading, spacing: 0.5) {
            Text(title)
                .font(EtubuClusterFonts.ui(max(5.5, height * 0.052 * contentScale), weight: .bold))
                .tracking(0.3)
                .foregroundStyle(theme.mutedText.opacity(0.80))
                .lineLimit(1)
                .minimumScaleFactor(0.70)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(valStr)
                    .font(EtubuClusterFonts.ui(max(8.5, height * 0.088 * contentScale), weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(valColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)

                Text(unitStr)
                    .font(EtubuClusterFonts.ui(max(4.8, height * 0.046 * contentScale), weight: .bold))
                    .foregroundStyle(theme.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(valStr) \(unitStr)")
    }
}
