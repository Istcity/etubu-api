import SwiftUI

struct EtubuTPMSGridView: View {
    @ObservedObject var telemetry: EtubuVehicleTelemetry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 14) {
                tireCell("FL", telemetry.tpmsFL)
                tireCell("FR", telemetry.tpmsFR)
            }
            HStack(spacing: 14) {
                tireCell("RL", telemetry.tpmsRL)
                tireCell("RR", telemetry.tpmsRR)
            }
        }
        .font(.caption.monospacedDigit())
    }

    private func tireCell(_ name: String, _ tire: EtubuTireReading) -> some View {
        HStack(spacing: 3) {
            Text(name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.4))
            // Keep value + unit as one run so they never wrap apart in narrow side cards
            if let psi = tire.psi {
                Text("\(String(format: "%.1f", psi)) psi")
                    .font(.system(.caption, design: .monospaced).weight(tire.warning ? .bold : .semibold))
                    .foregroundStyle(tire.warning ? Color.orange : Color.white.opacity(0.9))
            } else {
                Text("— psi")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.78)
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(1)
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

    var body: some View {
        if telemetry.isCharging || telemetry.chargePortOpen == true {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.green)
                if let kw = telemetry.chargeKw {
                    Text("\(kw) kW")
                        .font(.caption.weight(.bold).monospacedDigit())
                }
                if let a = telemetry.chargerAmps {
                    Text("\(a) A")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.55))
                }
                if let lim = telemetry.chargeLimitPercent {
                    Text("lim \(lim)%")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                }
                if let m = telemetry.minutesToFullCharge, m > 0 {
                    Text("\(m) dk")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.green.opacity(0.18)))
        }
    }
}

struct EtubuClosuresChip: View {
    @ObservedObject var telemetry: EtubuVehicleTelemetry

    var body: some View {
        HStack(spacing: 8) {
            if let locked = telemetry.locked {
                Label(locked ? "Kilitli" : "Açık", systemImage: locked ? "lock.fill" : "lock.open.fill")
                    .foregroundStyle(locked ? Color.white.opacity(0.55) : Color.orange)
            }
            if telemetry.anyDoorOpen {
                Label("Kapı", systemImage: "door.left.hand.open")
                    .foregroundStyle(.orange)
            }
            if telemetry.sentryActive == true {
                Label("Sentry", systemImage: "eye.fill")
                    .foregroundStyle(.red.opacity(0.85))
            }
        }
        .font(.caption2.weight(.semibold))
    }
}

struct EtubuPowerHistorySparkline: View {
    let samples: [Int]

    var body: some View {
        if samples.count >= 2 {
            GeometryReader { geo in
                let minV = CGFloat(samples.min() ?? 0)
                let maxV = CGFloat(samples.max() ?? 1)
                let span = max(40, max(abs(minV), abs(maxV), maxV - minV))
                let midY = geo.size.height / 2
                ZStack {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: midY))
                        p.addLine(to: CGPoint(x: geo.size.width, y: midY))
                    }
                    .stroke(Color.white.opacity(0.15), style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                    Path { path in
                        for (i, v) in samples.enumerated() {
                            let x = geo.size.width * CGFloat(i) / CGFloat(max(1, samples.count - 1))
                            let y = midY - (CGFloat(v) / span) * (geo.size.height * 0.45)
                            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                            else { path.addLine(to: CGPoint(x: x, y: y)) }
                        }
                    }
                    .stroke(
                        LinearGradient(colors: [.green.opacity(0.8), .orange.opacity(0.85)], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                    )
                }
            }
            .frame(height: 28)
        }
    }
}

/// Radar / corridor alert toggles — mirrored into Cap localStorage for web RadarAlert.
struct EtubuRadarSettingsView: View {
    @AppStorage("etubu_radar_beeps") private var beeps = true
    @AppStorage("etubu_radar_tts") private var tts = true
    @AppStorage("etubu_radar_cards") private var cards = true
    @AppStorage("etubu_radar_corridor") private var corridor = true

    var body: some View {
        Section("Radar / koridor uyarıları") {
            Toggle("Bip sesleri", isOn: $beeps)
            Toggle("Sesli uyarı (TTS)", isOn: $tts)
            Toggle("Uyarı kartları", isOn: $cards)
            Toggle("Hız koridoru paneli", isOn: $corridor)
        }
        .onChange(of: beeps) { _, _ in sync() }
        .onChange(of: tts) { _, _ in sync() }
        .onChange(of: cards) { _, _ in sync() }
        .onChange(of: corridor) { _, _ in sync() }
        .onAppear { sync() }
    }

    private func sync() {
        EtubuClusterAudioBridge.evalJS("""
        (function(){
          try {
            localStorage.setItem('etubu_radar_beeps', '\(beeps ? "1" : "0")');
            localStorage.setItem('etubu_radar_tts', '\(tts ? "1" : "0")');
            localStorage.setItem('etubu_radar_cards', '\(cards ? "1" : "0")');
            localStorage.setItem('etubu_radar_corridor', '\(corridor ? "1" : "0")');
            window.__etubuRadarPrefs = {
              beeps: \(beeps),
              tts: \(tts),
              cards: \(cards),
              corridor: \(corridor)
            };
          } catch(e) {}
        })();
        """)
    }
}
