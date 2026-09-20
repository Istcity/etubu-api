import SwiftUI

struct EtubuTPMSGridView: View {
    @ObservedObject var telemetry: EtubuVehicleTelemetry
    /// Burun yukarı çizim (dik + yatay sol kart).
    var noseUp: Bool = true
    var compact: Bool = false
    var maxWidth: CGFloat = 128
    var maxHeight: CGFloat = 112
    private var theme: ClusterTheme { ClusterTheme.stored }
    @AppStorage("etubu.tpms.unit.bar") private var showBarUnit = false

    /// Asset intrinsic ratio (EtubuCarTopUp 680×1408).
    private static let noseUpRatio: CGFloat = 680.0 / 1408.0
    private static let noseSideRatio: CGFloat = 1408.0 / 680.0

    var body: some View {
        let fit = Self.fit(in: CGSize(width: maxWidth, height: maxHeight), noseUp: noseUp, compact: compact)
        VStack(alignment: .leading, spacing: 2) {
            Group {
                if noseUp {
                    noseUpDiagram(carW: fit.carW, carH: fit.carH, gutter: fit.gutter)
                } else {
                    noseSideDiagram(carW: fit.carW, carH: fit.carH, gutter: fit.gutter)
                }
            }
            .frame(width: fit.totalW, height: fit.totalH, alignment: .center)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.easeInOut(duration: 0.2)) {
                    showBarUnit.toggle()
                }
            }
            .accessibilityIdentifier("etubu.tpms.grid")

            if telemetry.isAwaitingTPMS {
                Text(EtubuClusterL10n.t("awaitingTPMS"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .accessibilityIdentifier("etubu.tpms.awaiting")
            }
        }
        .frame(width: fit.totalW, height: fit.totalH, alignment: .leading)
    }

    private func noseUpDiagram(carW: CGFloat, carH: CGFloat, gutter: CGFloat) -> some View {
        let tirePad = carH * 0.15
        return HStack(alignment: .center, spacing: 0) {
            tireColumn(top: telemetry.tpmsFL, topId: "FL", bottom: telemetry.tpmsRL, bottomId: "RL", tirePad: tirePad)
                .frame(width: gutter, height: carH)

            carImage
                .frame(width: carW, height: carH)

            tireColumn(top: telemetry.tpmsFR, topId: "FR", bottom: telemetry.tpmsRR, bottomId: "RR", tirePad: tirePad)
                .frame(width: gutter, height: carH)
        }
        .frame(width: carW + gutter * 2, height: carH)
    }

    private func noseSideDiagram(carW: CGFloat, carH: CGFloat, gutter: CGFloat) -> some View {
        let tirePad = carW * 0.15
        return VStack(alignment: .center, spacing: 0) {
            HStack {
                Spacer(minLength: 0).frame(width: tirePad)
                psiText(telemetry.tpmsFL, corner: "FL")
                Spacer(minLength: 0)
                psiText(telemetry.tpmsRL, corner: "RL")
                Spacer(minLength: 0).frame(width: tirePad)
            }
            .frame(width: carW, height: gutter)

            carImage
                .frame(width: carW, height: carH)

            HStack {
                Spacer(minLength: 0).frame(width: tirePad)
                psiText(telemetry.tpmsFR, corner: "FR")
                Spacer(minLength: 0)
                psiText(telemetry.tpmsRR, corner: "RR")
                Spacer(minLength: 0).frame(width: tirePad)
            }
            .frame(width: carW, height: gutter)
        }
        .frame(width: carW, height: carH + gutter * 2)
    }

    private func tireColumn(
        top: EtubuTireReading,
        topId: String,
        bottom: EtubuTireReading,
        bottomId: String,
        tirePad: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0).frame(height: tirePad)
            psiText(top, corner: topId)
            Spacer(minLength: 0)
            psiText(bottom, corner: bottomId)
            Spacer(minLength: 0).frame(height: tirePad)
        }
    }

    private var carImage: some View {
        Image(noseUp ? "EtubuCarTopUp" : "EtubuCarTop")
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
            .foregroundStyle(theme.tpmsCarStroke)
            .accessibilityHidden(true)
    }

    private func psiText(_ tire: EtubuTireReading, corner: String) -> some View {
        let label: String = {
            if showBarUnit {
                if let bar = tire.bar { return String(format: "%.1f", bar) }
                if let psi = tire.psi { return String(format: "%.1f", psi * 0.0689476) }
            } else {
                if let psi = tire.psi { return "\(Int(psi.rounded()))" }
                if let bar = tire.bar { return "\(Int((bar / 0.0689476).rounded()))" }
            }
            return "-"
        }()
        let warn = tire.warning || (tire.psi.map { $0 < 32 || $0 > 48 } ?? false)
        return Text(label)
            .font(.system(size: compact ? (showBarUnit ? 9.5 : 11) : (showBarUnit ? 11 : 12.5), weight: warn ? .bold : .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(warn ? Color.orange : Color.white.opacity(0.92))
            .shadow(color: .black.opacity(0.7), radius: 2, y: 1)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity)
            .clipped()
            .accessibilityLabel("\(corner) \(label)")
            .accessibilityIdentifier("etubu.tpms.\(corner.lowercased())")
    }

    private struct Fit {
        var carW: CGFloat
        var carH: CGFloat
        var gutter: CGFloat
        var totalW: CGFloat
        var totalH: CGFloat
    }

    private static func fit(in budget: CGSize, noseUp: Bool, compact: Bool) -> Fit {
        let ratio: CGFloat = noseUp ? noseUpRatio : noseSideRatio
        let maxW = max(56, budget.width)
        let maxH = max(48, budget.height)
        let gutterCap: CGFloat = compact ? 24 : 28
        if noseUp {
            var gutter = min(gutterCap, max(16, maxW * 0.24))
            var carH = maxH
            var carW = carH * ratio
            if carW + gutter * 2 > maxW {
                gutter = max(16, min(gutter, (maxW - 28) / 2))
                carW = max(24, maxW - gutter * 2)
                carH = carW / ratio
            }
            if carH > maxH {
                carH = maxH
                carW = carH * ratio
                gutter = max(16, min(gutterCap, (maxW - carW) / 2))
            }
            return Fit(carW: carW, carH: carH, gutter: gutter, totalW: carW + gutter * 2, totalH: carH)
        }
        var gutter = min(gutterCap, max(16, maxH * 0.22))
        var carW = maxW
        var carH = carW / ratio
        if carH + gutter * 2 > maxH {
            gutter = max(16, min(gutter, (maxH - 28) / 2))
            carH = max(24, maxH - gutter * 2)
            carW = carH * ratio
        }
        return Fit(carW: carW, carH: carH, gutter: gutter, totalW: carW, totalH: carH + gutter * 2)
    }
}

struct EtubuMediaNowPlayingView: View {
    @ObservedObject var telemetry: EtubuVehicleTelemetry

    var body: some View {
        if !telemetry.mediaTitle.isEmpty || !telemetry.mediaArtist.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "music.note")
                    .foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text(telemetry.mediaTitle.isEmpty ? "—" : telemetry.mediaTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text([telemetry.mediaArtist, telemetry.mediaSource].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
        }
    }
}

struct EtubuChargeDetailChip: View {
    @ObservedObject var telemetry: EtubuVehicleTelemetry

    private var soc: CGFloat {
        let _ = telemetry.chargeEpoch
        return CGFloat(telemetry.displaySocPercent ?? 0) / 100
    }

    var body: some View {
        let _ = telemetry.chargeEpoch
        if telemetry.isCharging || telemetry.chargePortOpen == true || telemetry.displaySocPercent != nil {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: max(0.02, soc))
                        .stroke(
                            telemetry.isCharging ? Color.green : Color.cyan.opacity(0.9),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    Image(systemName: telemetry.isCharging ? "bolt.fill" : "battery.100")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(telemetry.isCharging ? Color.green : Color.white.opacity(0.7))
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(telemetry.displaySocPercent.map { "\($0)%" } ?? "—%")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                    HStack(spacing: 6) {
                        if let kw = telemetry.chargeKw, telemetry.isCharging {
                            Text("\(kw) kW")
                                .font(.caption2.weight(.semibold).monospacedDigit())
                        }
                        if let m = telemetry.minutesToFullCharge, m > 0, telemetry.isCharging {
                            Text("\(m) dk")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        if let range = telemetry.displayRangeKm {
                            Text("\(range) km")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.clear)
        }
    }
}

struct EtubuClosuresChip: View {
    @ObservedObject var telemetry: EtubuVehicleTelemetry

    var body: some View {
        HStack(spacing: 8) {
            if let locked = telemetry.locked {
                Label(
                    locked ? EtubuClusterL10n.t("lockLocked") : EtubuClusterL10n.t("lockOpen"),
                    systemImage: locked ? "lock.fill" : "lock.open.fill"
                )
                    .foregroundStyle(locked ? Color.white.opacity(0.55) : Color.orange)
            }
            if telemetry.anyDoorOpen {
                Label(EtubuClusterL10n.t("door"), systemImage: "door.left.hand.open")
                    .foregroundStyle(.orange)
            }
            if telemetry.sentryActive == true {
                Label(EtubuClusterL10n.t("sentry"), systemImage: "eye.fill")
                    .foregroundStyle(.red.opacity(0.85))
            }
        }
        .font(.caption2.weight(.semibold))
    }
}

struct EtubuPowerHistorySparkline: View {
    let samples: [Int]
    var compact: Bool = false

    var body: some View {
        if samples.count >= 2 {
            GeometryReader { geo in
                let minV = CGFloat(samples.min() ?? 0)
                let maxV = CGFloat(samples.max() ?? 1)
                let span = max(40, max(abs(minV), abs(maxV), maxV - minV))
                let midY = geo.size.height / 2
                let lw: CGFloat = compact ? 1.2 : 1.5
                ZStack {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: midY))
                        p.addLine(to: CGPoint(x: geo.size.width, y: midY))
                    }
                    .stroke(Color.white.opacity(compact ? 0.12 : 0.15), style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))

                    Path { path in
                        var started = false
                        for (i, v) in samples.enumerated() {
                            let x = geo.size.width * CGFloat(i) / CGFloat(max(1, samples.count - 1))
                            let y = midY - (CGFloat(min(0, v)) / span) * (geo.size.height * 0.45)
                            if !started { path.move(to: CGPoint(x: x, y: midY)); started = true }
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    .stroke(
                        Color(red: 0.3, green: 0.9, blue: 0.55).opacity(0.85),
                        style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round)
                    )

                    Path { path in
                        var started = false
                        for (i, v) in samples.enumerated() {
                            let x = geo.size.width * CGFloat(i) / CGFloat(max(1, samples.count - 1))
                            let y = midY - (CGFloat(max(0, v)) / span) * (geo.size.height * 0.45)
                            if !started { path.move(to: CGPoint(x: x, y: midY)); started = true }
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.orange.opacity(0.75),
                                Color(red: 1.0, green: 0.85, blue: 0.25).opacity(0.9),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round)
                    )
                }
            }
            .frame(height: compact ? 14 : 28)
        }
    }
}

/// Radar / corridor alert toggles — bip açık; TTS mesafe söylemez.
struct EtubuRadarSettingsView: View {
    @AppStorage("etubu_radar_beeps") private var beeps = true
    @AppStorage("etubu_radar_tts") private var tts = true
    @AppStorage("etubu_radar_cards") private var cards = true
    @AppStorage("etubu_radar_corridor") private var corridor = true
    @ObservedObject private var premium = EtubuPremiumManager.shared

    var body: some View {
        Section {
            Toggle(EtubuClusterL10n.t("warnBeeps"), isOn: $beeps)
                .disabled(!premium.isPremium)
            Toggle(EtubuClusterL10n.t("warnCards"), isOn: $cards)
                .disabled(!premium.isPremium)
            Toggle(EtubuClusterL10n.t("warnCorridor"), isOn: $corridor)
                .disabled(!premium.isPremium)
            Text(premium.isPremium ? EtubuClusterL10n.t("warnSoundsHint") : EtubuClusterL10n.t("premiumLockedWarn"))
                .font(EtubuClusterFonts.ui(12, weight: .medium))
                .foregroundStyle(ClusterTheme.stored.mutedText)
        } header: {
            HStack {
                EtubuSheetSectionTitle(title: EtubuClusterL10n.t("warnSoundsSection"), theme: ClusterTheme.stored, motion: .alerts)
                if !premium.isPremium {
                    EtubuPremiumBadge(compact: true)
                }
            }
        }
        .etubuSheetSection(ClusterTheme.stored)
        .onChange(of: beeps) { _, _ in sync() }
        .onChange(of: cards) { _, _ in sync() }
        .onChange(of: corridor) { _, _ in sync() }
        .onAppear {
            tts = false
            UserDefaults.standard.set(false, forKey: "etubu_radar_tts")
            sync()
        }
    }

    private func sync() {
        let p = premium.isPremium
        EtubuClusterAudioBridge.evalJS("""
        (function(){
          try {
            localStorage.setItem('etubu_radar_beeps', '\(p && beeps ? "1" : "0")');
            localStorage.setItem('etubu_radar_tts', '0');
            localStorage.setItem('etubu_radar_cards', '\(p && cards ? "1" : "0")');
            localStorage.setItem('etubu_radar_corridor', '\(p && corridor ? "1" : "0")');
            window.__etubuRadarPrefs = {
              beeps: \(p && beeps),
              tts: false,
              cards: \(p && cards),
              corridor: \(p && corridor)
            };
          } catch(e) {}
        })();
        """)
    }
}

/// Landscape right rail over the map — SoC, remain, consumption in ground-contrast ink.
struct EtubuMapDriveReadout: View {
    let theme: ClusterTheme
    var soc: Int?
    var rangeKm: Int?
    var remainLabel: String
    var whPerKm: Double?
    var tripKwh: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "bolt.car.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.mapHudMuted)
                Text(soc.map { "\($0)%" } ?? "—")
                    .font(EtubuClusterFonts.ui(18, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(theme.mapHudText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let rangeKm {
                    Text("\(rangeKm) km")
                        .font(EtubuClusterFonts.ui(13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(theme.mapHudMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
            }
            if !remainLabel.isEmpty {
                labeled(EtubuClusterL10n.distance, remainLabel)
            }
            if let whPerKm, whPerKm > 0 {
                let kwhBit: String = {
                    guard let tripKwh, tripKwh > 0.05 else { return "" }
                    return String(format: " · %.1f kWh", tripKwh)
                }()
                labeled(
                    EtubuClusterL10n.t("tripStatAvgWh"),
                    String(format: "%.0f Wh/km", whPerKm) + kwhBit
                )
            }
        }
        .shadow(color: .black.opacity(0.85), radius: 1.4, y: 1)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("etubu.map.driveReadout")
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(EtubuClusterFonts.ui(10, weight: .semibold))
                .foregroundStyle(theme.mapHudMuted)
                .lineLimit(1)
            Text(value)
                .font(EtubuClusterFonts.ui(15, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(theme.mapHudText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}
