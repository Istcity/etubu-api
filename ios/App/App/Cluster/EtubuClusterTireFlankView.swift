import SwiftUI

/// Left / Right TPMS flank view that sits beside the central warning/corridor stack in landscape.
struct EtubuClusterTireFlankView: View {
    enum Side {
        case left
        case right
    }

    let side: Side
    let theme: ClusterTheme
    var scale: CGFloat = 1.0
    var transparentBg: Bool = false
    var showLabels: Bool = true

    @ObservedObject private var telemetry = EtubuVehicleTelemetry.shared
    @AppStorage("etubu.tpms.unit.bar") private var showBarUnit = false

    private var frontTire: EtubuTireReading {
        side == .left ? telemetry.tpmsFL : telemetry.tpmsFR
    }

    private var rearTire: EtubuTireReading {
        side == .left ? telemetry.tpmsRL : telemetry.tpmsRR
    }

    private func formatPressure(_ reading: EtubuTireReading) -> String {
        if showBarUnit {
            if let bar = reading.bar {
                return String(format: "%.1f", bar)
            }
            if let psi = reading.psi {
                return String(format: "%.1f", psi * 0.0689476)
            }
        } else {
            if let psi = reading.psi {
                return "\(Int(psi.rounded()))"
            }
            if let bar = reading.bar {
                return "\(Int((bar / 0.0689476).rounded()))"
            }
        }
        return "—"
    }

    private func pressureColor(_ reading: EtubuTireReading) -> Color {
        if reading.warning { return Color(red: 1.0, green: 0.28, blue: 0.28) }
        guard let psi = reading.psi ?? (reading.bar.map { $0 / 0.0689476 }) else {
            return theme.secondaryText
        }
        if psi < 32 { return Color(red: 1.0, green: 0.65, blue: 0.15) }
        if psi > 46 { return Color(red: 1.0, green: 0.75, blue: 0.2) }
        return theme.accent
    }

    private var unitLabel: String {
        showBarUnit ? "bar" : "psi"
    }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeInOut(duration: 0.2)) {
                showBarUnit.toggle()
            }
        } label: {
            VStack(spacing: max(4, 6 * scale)) {
                // Front Tire
                tireCell(
                    posLabel: side == .left ? EtubuClusterL10n.t("tireFL") : EtubuClusterL10n.t("tireFR"),
                    reading: frontTire,
                    isFront: true
                )

                // Subtle vehicle axis divider
                if showLabels {
                    Rectangle()
                        .fill(theme.stroke.opacity(0.4))
                        .frame(height: 1)
                        .padding(.horizontal, 4)
                }

                // Rear Tire
                tireCell(
                    posLabel: side == .left ? EtubuClusterL10n.t("tireRL") : EtubuClusterL10n.t("tireRR"),
                    reading: rearTire,
                    isFront: false
                )
            }
            .padding(.vertical, max(3, 5 * scale))
            .padding(.horizontal, max(2, 4 * scale))
            .background(
                Group {
                    if !transparentBg {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(theme.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(theme.stroke.opacity(0.55), lineWidth: 1)
                            )
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(side == .left ? "etubu.tpms.flank.left" : "etubu.tpms.flank.right")
    }

    @ViewBuilder
    private func tireCell(posLabel: String, reading: EtubuTireReading, isFront: Bool) -> some View {
        let pColor = pressureColor(reading)
        VStack(spacing: 1) {
            if showLabels {
                HStack(spacing: 3) {
                    Image(systemName: isFront ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        .font(EtubuClusterFonts.ui(max(7, 8 * scale), weight: .semibold))
                        .foregroundStyle(theme.mutedText)

                    Text(posLabel)
                        .font(EtubuClusterFonts.ui(max(8, 9 * scale), weight: .bold))
                        .foregroundStyle(theme.mutedText)
                        .lineLimit(1)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(formatPressure(reading))
                    .font(EtubuClusterFonts.ui(max(13, (showLabels ? 15 : 17) * scale), weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(pColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(unitLabel)
                    .font(EtubuClusterFonts.ui(max(7, 8 * scale), weight: .medium))
                    .foregroundStyle(theme.mutedText)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
