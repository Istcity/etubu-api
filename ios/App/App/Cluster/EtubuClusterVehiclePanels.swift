import SwiftUI

struct EtubuTPMSGridView: View {
    @ObservedObject var telemetry: EtubuVehicleTelemetry
    /// Burun yukarı çizim (dik + yatay sol kart).
    var noseUp: Bool = true
    var compact: Bool = false
    private var theme: ClusterTheme { ClusterTheme.stored }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ZStack {
                // Kontur-only (şeffaf dolgu) — tema canvas arkadan görünür
                Image(noseUp ? "EtubuCarTopUp" : "EtubuCarTop")
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .foregroundStyle(theme.tpmsCarStroke)
                    .accessibilityHidden(true)

                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    if noseUp {
                        psiText(telemetry.tpmsFL, corner: "FL").position(x: w * 0.05, y: h * 0.20)
                        psiText(telemetry.tpmsFR, corner: "FR").position(x: w * 0.95, y: h * 0.20)
                        psiText(telemetry.tpmsRL, corner: "RL").position(x: w * 0.05, y: h * 0.80)
                        psiText(telemetry.tpmsRR, corner: "RR").position(x: w * 0.95, y: h * 0.80)
                    } else {
                        psiText(telemetry.tpmsFL, corner: "FL").position(x: w * 0.20, y: h * 0.05)
                        psiText(telemetry.tpmsFR, corner: "FR").position(x: w * 0.20, y: h * 0.95)
                        psiText(telemetry.tpmsRL, corner: "RL").position(x: w * 0.80, y: h * 0.05)
                        psiText(telemetry.tpmsRR, corner: "RR").position(x: w * 0.80, y: h * 0.95)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(noseUp ? (680.0 / 1408.0) : (1408.0 / 680.0), contentMode: .fit)
            // Yatay eski 188 → 132 (−%30)
            .frame(maxHeight: 132)
            .background(Color.clear)
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func psiText(_ tire: EtubuTireReading, corner: String) -> some View {
        let label: String = {
            if let psi = tire.psi { return String(format: "%.0f", psi) }
            return "-"
        }()
        let warn = tire.warning || (tire.psi.map { $0 < 32 || $0 > 48 } ?? false)
        return Text(label)
            .font(.system(size: compact ? 12 : 14, weight: warn ? .bold : .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(warn ? Color.orange : Color.white.opacity(0.92))
            .shadow(color: .black.opacity(0.7), radius: 2, y: 1)
            .accessibilityLabel("\(corner) \(label)")
            .accessibilityIdentifier("etubu.tpms.\(corner.lowercased())")
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
        CGFloat(telemetry.displaySocPercent ?? telemetry.socPercent ?? 0) / 100
    }

    var body: some View {
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
            if EtubuAppLanguage.current.warnTtsEnabled {
                Toggle(EtubuClusterL10n.t("warnTts"), isOn: $tts)
                    .disabled(!premium.isPremium)
            }
            Toggle(EtubuClusterL10n.t("warnCards"), isOn: $cards)
                .disabled(!premium.isPremium)
            Toggle(EtubuClusterL10n.t("warnCorridor"), isOn: $corridor)
                .disabled(!premium.isPremium)
            Text(premium.isPremium ? EtubuClusterL10n.t("warnSoundsHint") : EtubuClusterL10n.t("premiumLockedWarn"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        } header: {
            HStack {
                Text(EtubuClusterL10n.t("warnSoundsSection"))
                if !premium.isPremium {
                    EtubuPremiumBadge(compact: true)
                }
            }
        }
        .onChange(of: beeps) { _, _ in sync() }
        .onChange(of: tts) { _, _ in sync() }
        .onChange(of: cards) { _, _ in sync() }
        .onChange(of: corridor) { _, _ in sync() }
        .onAppear { sync() }
    }

    private func sync() {
        let p = premium.isPremium
        EtubuClusterAudioBridge.evalJS("""
        (function(){
          try {
            localStorage.setItem('etubu_radar_beeps', '\(p && beeps ? "1" : "0")');
            localStorage.setItem('etubu_radar_tts', '\(p && tts ? "1" : "0")');
            localStorage.setItem('etubu_radar_cards', '\(p && cards ? "1" : "0")');
            localStorage.setItem('etubu_radar_corridor', '\(p && corridor ? "1" : "0")');
            window.__etubuRadarPrefs = {
              beeps: \(p && beeps),
              tts: \(p && tts),
              cards: \(p && cards),
              corridor: \(p && corridor)
            };
          } catch(e) {}
        })();
        """)
    }
}
