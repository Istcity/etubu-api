import SwiftUI

struct EtubuSpeedDialView: View {
    let kmh: Int
    let gear: String
    let theme: ClusterTheme
    var compact: Bool = false
    /// Optional override — landscape Dynamic Island uses smaller dial to avoid overflow.
    var diameter: CGFloat? = nil
    /// Gear / km/h / kW sizing; defaults to diameter. Use base size when dial is enlarged.
    var chromeDiameter: CGFloat? = nil
    var powerKw: Int? = nil
    /// Son güç örnekleri — kadran altı sparkline (regen/drive).
    var powerHistory: [Int] = []
    /// SoC ince halka (0–100).
    var socPercent: Int? = nil
    @ObservedObject private var warnings = EtubuDriveWarnings.shared
    /// Soft display lerp — keskin sıçrama yok, yumuşak yükseliş.
    @State private var displayKmh: Double = 0
    @State private var displayPower: Double = 0
    @State private var boostPulse: CGFloat = 0

    private var rawKmh: Int { warnings.demoActive ? warnings.demoKmh : kmh }
    private var shownGear: String {
        if warnings.demoActive {
            let g = warnings.demoGear
            if (g.isEmpty || g == "P"), warnings.demoKmh >= 5 { return "D" }
            return g.isEmpty ? "D" : g
        }
        return gear
    }
    /// P/N → kadran kilitli 0; düşük hızı gizleme (yumuşak artış).
    private var isStationary: Bool {
        let g = shownGear.uppercased()
        return g.hasPrefix("P") || g.hasPrefix("N")
    }
    private var targetKmh: Int { isStationary ? 0 : rawKmh }
    private var shownKmh: Int { Int(displayKmh.rounded()) }
    private var shownPowerKw: Int? {
        let raw = warnings.demoActive ? warnings.demoPowerKw : powerKw
        guard let raw else { return nil }
        if isStationary { return abs(raw) < 6 ? 0 : raw }
        if abs(raw) < 4 { return 0 }
        return raw
    }

    private var dialSize: CGFloat { diameter ?? (compact ? 200 : 280) }
    private var chromeSize: CGFloat { chromeDiameter ?? dialSize }
    private var textBoost: CGFloat { compact ? 1.22 * 1.15 : 1.22 }
    private var tripleDigitFactor: CGFloat { shownKmh >= 100 ? 0.74 : (shownKmh >= 10 ? 0.92 : 1.0) }

    private var speedFont: CGFloat {
        let base: CGFloat = compact
            ? max(64, min(dialSize * 0.32, 110))
            : max(92, min(dialSize * 0.38, 124))
        return base * textBoost * min(theme.gaugeScale, 1.04) * tripleDigitFactor
    }

    private var gearFont: CGFloat {
        let base: CGFloat = compact
            ? max(16, min(chromeSize * 0.09, 24))
            : max(18, min(chromeSize * 0.085, 28))
        return base
    }

    private var unitFont: CGFloat {
        let base: CGFloat = compact
            ? max(10, min(chromeSize * 0.050, 15))
            : max(13, min(chromeSize * 0.058, 18))
        return base * textBoost * (shownKmh >= 100 ? 0.9 : 1)
    }

    private var kwFont: CGFloat {
        compact ? max(10, min(chromeSize * 0.045, 14)) : max(12, min(chromeSize * 0.048, 16))
    }

    private var speedProgress: CGFloat { min(1, CGFloat(max(0, shownKmh)) / 180) }
    private var power: Int { Int(displayPower.rounded()) }
    private var powerFill: CGFloat { min(1, CGFloat(abs(displayPower)) / 160) }
    private var boostStrength: CGFloat {
        guard !isStationary else { return 0 }
        if power > 40 { return min(1, CGFloat(power) / 220) }
        return 0
    }
    private var sparkSamples: [Int] {
        let src = powerHistory.isEmpty ? [power] : powerHistory
        return Array(src.suffix(28))
    }
    private var socProgress: CGFloat {
        guard let soc = socPercent else { return 0 }
        return min(1, max(0, CGFloat(soc) / 100))
    }

    private var ringClearance: CGFloat {
        guard compact else { return dialSize * 0.05 }
        return theme.ringLineWidth(for: dialSize) * 1.8 + dialSize * 0.03
    }

    var body: some View {
        ZStack {
            if compact { dialRings }

            // Soft boost wash — hızlanmada yumuşak ışık, keskin flaş değil.
            if boostStrength > 0.05 {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                theme.accent.opacity(0.22 * boostStrength + 0.06 * boostPulse),
                                theme.accent.opacity(0.06 * boostStrength),
                                .clear,
                            ],
                            center: .center,
                            startRadius: dialSize * 0.12,
                            endRadius: dialSize * 0.52
                        )
                    )
                    .frame(width: dialSize * 0.92, height: dialSize * 0.92)
                    .allowsHitTesting(false)
                    .animation(.easeOut(duration: 0.35), value: boostStrength)
            }

            VStack(spacing: compact ? max(1, dialSize * 0.008) : 5) {
                gearRow
                Text("\(shownKmh)")
                    .font(EtubuClusterFonts.gauge(speedFont))
                    .monospacedDigit()
                    .tracking(shownKmh >= 100 ? 0 : min(theme.gaugeTracking, 0.8) * 0.06)
                    .foregroundStyle(theme.primaryText)
                    .shadow(
                        color: isStationary ? .clear : theme.accent.opacity(0.4),
                        radius: compact ? 8 : 6
                    )
                    .minimumScaleFactor(0.38)
                    .lineLimit(1)
                    .frame(maxWidth: dialSize * (shownKmh >= 100 ? 0.78 : 0.70))
                    .accessibilityIdentifier("etubu.speed")
                    .contentTransition(.identity)
                Text("km/h")
                    .font(EtubuClusterFonts.ui(unitFont, weight: .semibold))
                    .foregroundStyle(theme.mutedText)
                    .tracking(min(theme.gaugeTracking, 0.8) * 0.4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if warnings.demoActive {
                    Button {
                        EtubuDemoDrive.shared.stop()
                    } label: {
                        Text(EtubuClusterL10n.t("demoStop"))
                            .font(EtubuClusterFonts.ui(compact ? 9 : 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, compact ? 8 : 10)
                            .padding(.vertical, compact ? 4 : 5)
                            .background(Capsule().fill(Color.red.opacity(0.92)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(EtubuClusterL10n.t("demoStop"))
                    .accessibilityIdentifier("etubu.demo.stop")
                }

                if compact {
                    Text(shownPowerKw.map { "\($0) kW" } ?? "— kW")
                        .font(EtubuClusterFonts.gauge(kwFont))
                        .monospacedDigit()
                        .foregroundStyle(
                            power < -1
                            ? Color(red: 0.35, green: 0.92, blue: 0.55)
                            : (power > 1 ? theme.accent : theme.mutedText)
                        )
                        .minimumScaleFactor(0.65)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, max(4, ringClearance * 0.55))
            .padding(.vertical, ringClearance * 0.7)
            .frame(maxWidth: dialSize * 0.88, maxHeight: dialSize * 0.88)
        }
        .frame(width: dialSize, height: dialSize)
        .transaction { txn in
            if isStationary { txn.animation = nil }
        }
        .onAppear {
            displayKmh = Double(targetKmh)
            displayPower = Double(shownPowerKw ?? 0)
        }
        .onChange(of: targetKmh) { _, new in
            if new == 0 || isStationary {
                withAnimation(.easeOut(duration: 0.35)) { displayKmh = 0 }
                return
            }
            withAnimation(.interpolatingSpring(stiffness: 70, damping: 16)) {
                displayKmh = Double(new)
            }
        }
        .onChange(of: shownPowerKw) { _, new in
            let v = Double(new ?? 0)
            withAnimation(.easeInOut(duration: 0.32)) {
                displayPower = v
            }
            guard v > 55 else {
                withAnimation(.easeOut(duration: 0.4)) { boostPulse = 0 }
                return
            }
            withAnimation(.easeOut(duration: 0.25)) { boostPulse = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                withAnimation(.easeOut(duration: 0.55)) { boostPulse = 0.35 }
            }
        }
        .animation(.easeInOut(duration: 0.28), value: displayPower)
    }

    @ViewBuilder
    private var dialRings: some View {
        let lw = theme.ringLineWidth(for: dialSize)
        let moving = !isStationary
        ZStack {
            Circle()
                .strokeBorder(theme.stroke.opacity(0.40), lineWidth: lw)

            // SoC ince halka — hız halkasının dışında.
            if socProgress > 0 {
                Circle()
                    .trim(from: 0, to: max(0.02, socProgress))
                    .stroke(
                        theme.accent.opacity(0.55),
                        style: StrokeStyle(lineWidth: max(2, lw * 0.45), lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .padding(lw * 0.15)
                    .opacity(0.85)
            }

            if moving {
                movingRingFill(lineWidth: lw)
                bipolarPowerRing(lineWidth: lw)
            } else {
                Circle()
                    .strokeBorder(theme.accent.opacity(0.28), lineWidth: lw * 1.05)
            }
        }
        .frame(width: dialSize, height: dialSize)
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.48), value: shownKmh)
        .animation(.easeOut(duration: 0.4), value: socProgress)
        .animation(.easeInOut(duration: 0.28), value: displayPower)
    }

    @ViewBuilder
    private func movingRingFill(lineWidth lw: CGFloat) -> some View {
        switch theme.dialRingStyle {
        case .neonSweep:
            Circle()
                .trim(from: 0, to: max(0.02, speedProgress))
                .stroke(
                    AngularGradient(
                        colors: [
                            theme.accent.opacity(0.15),
                            theme.accent,
                            Color.white.opacity(0.95),
                            theme.accent,
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lw * 1.55, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: theme.accent.opacity(0.85), radius: 10)

        case .dualGlow:
            Circle()
                .strokeBorder(theme.accent.opacity(0.28), lineWidth: lw * 2.1)
            Circle()
                .trim(from: 0, to: max(0.02, speedProgress))
                .stroke(theme.accent, style: StrokeStyle(lineWidth: lw * 1.45, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: theme.accent.opacity(0.75), radius: 12)

        case .dashed:
            Circle()
                .strokeBorder(theme.accent.opacity(0.7), style: StrokeStyle(lineWidth: lw * 1.2, dash: [7, 5]))
            Circle()
                .trim(from: 0, to: max(0.02, speedProgress))
                .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: lw * 0.85, lineCap: .round))
                .rotationEffect(.degrees(-90))

        case .plasmaRibbon:
            Circle()
                .trim(from: 0, to: max(0.02, speedProgress))
                .stroke(
                    AngularGradient(
                        colors: [
                            theme.accent.opacity(0.2),
                            Color(hue: theme.hue / 360, saturation: 0.9, brightness: 1),
                            Color(hue: ((theme.hue + 40).truncatingRemainder(dividingBy: 360)) / 360, saturation: 0.85, brightness: 1),
                            theme.accent.opacity(0.2),
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lw * 1.75, lineCap: .round)
                )
                .rotationEffect(.degrees(-90 + Double(shownKmh) * 0.15))
                .shadow(color: theme.glow.opacity(1), radius: 12)

        case .plaidHeat:
            Circle()
                .trim(from: 0, to: max(0.02, speedProgress))
                .stroke(
                    AngularGradient(
                        colors: [
                            Color(red: 1.0, green: 0.92, blue: 0.25),
                            Color(red: 1.0, green: 0.55, blue: 0.08),
                            Color(red: 0.95, green: 0.12, blue: 0.08),
                            Color(red: 0.75, green: 0.02, blue: 0.05),
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lw * 1.85, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: Color.orange.opacity(0.9), radius: 14)

        case .thin:
            Circle()
                .strokeBorder(theme.accent.opacity(0.55 + 0.25 * speedProgress), lineWidth: lw * 1.15)
                .shadow(color: theme.glow.opacity(1), radius: 8)
        }
    }

    private func bipolarPowerRing(lineWidth: CGFloat) -> some View {
        let regen = power < -1
        let drive = power > 1
        let fill = powerFill
        let track = lineWidth * 1.35
        return ZStack {
            Circle()
                .trim(from: 0.12, to: 0.88)
                .stroke(Color.white.opacity(0.10), style: StrokeStyle(lineWidth: track, lineCap: .round))
                .rotationEffect(.degrees(90))

            if regen {
                Circle()
                    .trim(from: 0.50 - 0.38 * fill, to: 0.50)
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color(red: 0.2, green: 0.9, blue: 0.5).opacity(0.35),
                                Color(red: 0.35, green: 0.95, blue: 0.65),
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: track * 1.15, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90))
                    .shadow(color: Color.green.opacity(0.6), radius: 8)
            }

            if drive {
                Circle()
                    .trim(from: 0.50, to: 0.50 + 0.38 * fill)
                    .stroke(
                        AngularGradient(
                            colors: [
                                theme.accent.opacity(0.4),
                                Color.orange,
                                Color.yellow.opacity(0.9),
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: track * 1.15, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90))
                    .shadow(color: Color.orange.opacity(0.55), radius: 8)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: displayPower)
    }

    private var gearRow: some View {
        Text(shownGear.isEmpty ? "P" : String(shownGear.prefix(1)))
            .font(EtubuClusterFonts.gauge(gearFont, weight: .bold))
            .foregroundStyle(theme.accent)
            .minimumScaleFactor(0.7)
            .lineLimit(1)
            .frame(height: gearFont * 1.15)
            .accessibilityIdentifier("etubu.gear")
    }
}

enum EtubuHazardChrome {
    static func icon(_ kind: String) -> String {
        switch kind {
        case "corridor": return "gauge.with.dots.needle.67percent"
        case "charge": return "bolt.fill"
        case "weather": return "cloud.rain.fill"
        case "control": return "shield.fill"
        default: return "camera.metering.spot"
        }
    }

    static func kicker(_ kind: String, urgent: Bool) -> String {
        switch kind {
        case "corridor": return EtubuClusterL10n.t("warnKickerCorridor")
        case "charge": return EtubuClusterL10n.t("warnKickerCharge")
        case "weather": return EtubuClusterL10n.t("warnKickerWeather")
        case "control": return EtubuClusterL10n.t("warnKickerControl")
        default: return urgent ? EtubuClusterL10n.t("warnKickerCritical") : EtubuClusterL10n.t("warnKickerRadar")
        }
    }

    /// TTS için TR kök — EtubuWarnVoice composeKeys ile uyumlu.
    static func speakRootTR(_ kind: String) -> String {
        switch kind {
        case "corridor": return "hız koridoru"
        case "charge": return "şarj istasyonu"
        case "weather": return "hava olayı"
        case "control": return "kontrol"
        default: return "radar"
        }
    }

    /// Web `.hud-map-mark--*` palette — cluster themes use accent for default radar when not urgent.
    static func tint(_ kind: String, urgent: Bool, theme: ClusterTheme) -> Color {
        switch kind {
        case "corridor": return Color(red: 1.0, green: 0.76, blue: 0.30) // #ffc14d
        case "charge": return Color(red: 0.18, green: 1.0, blue: 0.60) // #2dff9a
        case "weather": return Color(red: 0.56, green: 0.78, blue: 1.0) // #8ec8ff
        case "control": return Color(red: 1.0, green: 0.54, blue: 0.30) // #ff8a4d
        default: return urgent ? Color(red: 1.0, green: 0.35, blue: 0.35) : theme.accent
        }
    }

    /// Fixed HUD fills for map pins (independent of theme accent).
    static func mapFill(_ kind: String) -> Color {
        switch kind {
        case "corridor": return Color(red: 1.0, green: 0.76, blue: 0.30)
        case "charge": return Color(red: 0.18, green: 1.0, blue: 0.60)
        case "weather": return Color(red: 0.56, green: 0.78, blue: 1.0)
        case "control": return Color(red: 1.0, green: 0.54, blue: 0.30)
        default: return Color(red: 1.0, green: 0.35, blue: 0.35) // #ff5a5a
        }
    }
}

/// Harita hazard marker — web HUD mark (halo + tinted disc + dark glyph).
struct EtubuMapHazardMark: View {
    let kind: String
    let theme: ClusterTheme
    var compact: Bool = true

    private var fill: Color { EtubuHazardChrome.mapFill(kind) }
    private var core: CGFloat { compact ? 18 : 22 }

    var body: some View {
        ZStack {
            // Halo — web .hud-map-mark-halo
            Circle()
                .fill(Color(red: 0.02, green: 0.05, blue: 0.09).opacity(0.88))
                .frame(width: core + 8, height: core + 8)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.55), lineWidth: 1.2)
                )

            // Core disc
            Circle()
                .fill(fill)
                .frame(width: core, height: core)
                .overlay(
                    Circle()
                        .strokeBorder(Color(red: 0.02, green: 0.06, blue: 0.09), lineWidth: 1.4)
                )

            Image(systemName: EtubuHazardChrome.icon(kind))
                .font(.system(size: compact ? 9 : 11, weight: .bold))
                .foregroundStyle(Color(red: 0.02, green: 0.06, blue: 0.09))
        }
        .shadow(color: fill.opacity(0.85), radius: 5, y: 0)
        .accessibilityLabel(EtubuHazardChrome.kicker(kind, urgent: false))
    }
}

/// Araç konumu — şık kuzey oku + halo.
struct EtubuMapVehicleMark: View {
    var headingDeg: Double?

    var body: some View {
        let red = Color(red: 0.86, green: 0.08, blue: 0.24)
        ZStack {
            Circle()
                .fill(Color(red: 0.02, green: 0.05, blue: 0.09).opacity(0.75))
                .frame(width: 28, height: 28)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.45), lineWidth: 1.1))
            Image(systemName: "location.north.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(red)
                .rotationEffect(.degrees(headingDeg ?? 0))
                .shadow(color: red.opacity(0.75), radius: 5)
        }
    }
}

struct EtubuWarnBannerView: View {
    let item: EtubuWarnItem
    let theme: ClusterTheme

    private var urgent: Bool {
        item.stage == .critical || item.stage == .near
    }

    private var tint: Color {
        EtubuHazardChrome.tint(item.kind, urgent: urgent, theme: theme)
    }

    var body: some View {
        // Yazı sabit; yalnızca renk nabız atar (ölçek/opacity blink yok)
        TimelineView(.animation(minimumInterval: urgent ? 1.0 / 8.0 : 1.0, paused: !urgent)) { timeline in
            let pulse = urgent
                ? (0.55 + 0.45 * abs(sin(timeline.date.timeIntervalSinceReferenceDate * 3.2)))
                : 1.0
            let liveTint = tint.opacity(pulse)
            HStack(spacing: 12) {
                Image(systemName: EtubuHazardChrome.icon(item.kind))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(liveTint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(EtubuHazardChrome.kicker(item.kind, urgent: urgent))
                        .font(EtubuClusterFonts.ui(10, weight: .heavy))
                        .tracking(1)
                        .foregroundStyle(liveTint)
                    Text(item.title)
                        .font(EtubuClusterFonts.ui(15, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(2)
                    if !item.meta.isEmpty {
                        Text(item.meta)
                            .font(EtubuClusterFonts.ui(11, weight: .medium))
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if !item.distanceLabel.isEmpty {
                    Text(item.distanceLabel)
                        .font(EtubuClusterFonts.gauge(20))
                        .monospacedDigit()
                        .foregroundStyle(theme.primaryText)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(liveTint.opacity(0.75), lineWidth: 1.2)
                    )
            )
            .shadow(color: liveTint.opacity(urgent ? 0.45 : 0.25), radius: urgent ? 12 : 6)
        }
    }
}

/// Web `#hudWarnSide` — title + distance (primary road warning under avg column).
struct EtubuHudWarnSideView: View {
    let item: EtubuWarnItem
    let theme: ClusterTheme
    var compact: Bool = false
    /// When true, no fill / stroke chrome around the warning.
    var frameless: Bool = true
    /// Scale labels / distance numerals (portrait ~1.1, landscape ~1.3).
    var contentScale: CGFloat = 1

    private var urgent: Bool {
        item.stage == .critical || item.stage == .near
    }

    private var tint: Color {
        EtubuHazardChrome.tint(item.kind, urgent: urgent, theme: theme)
    }

    private var stageOpacity: Double {
        switch item.stage {
        case .critical: return 1
        case .near: return 0.95
        case .mid: return 0.78
        case .far: return 0.55
        case .idle: return 0.35
        }
    }

    var body: some View {
        // Mesafe/başlık sabit; kritikte yalnızca renk nabız atar
        TimelineView(.animation(minimumInterval: urgent ? 1.0 / 8.0 : 1.0, paused: !urgent)) { timeline in
            let pulse = urgent
                ? (0.55 + 0.45 * abs(sin(timeline.date.timeIntervalSinceReferenceDate * 3.2)))
                : 1.0
            let liveTint = tint.opacity(pulse)
            VStack(spacing: 4) {
                Text(item.title.isEmpty ? EtubuHazardChrome.kicker(item.kind, urgent: urgent) : item.title)
                    .font(EtubuClusterFonts.ui((compact ? 11 : 12) * contentScale, weight: .bold))
                    .foregroundStyle(liveTint)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(item.distanceLabel.isEmpty ? "—" : item.distanceLabel)
                    .font(EtubuClusterFonts.gauge((compact ? 22 : 28) * contentScale))
                    .monospacedDigit()
                    .foregroundStyle(theme.primaryText)
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
                if !item.meta.isEmpty {
                    Text(item.meta)
                        .font(EtubuClusterFonts.ui(10 * contentScale, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.vertical, compact ? 8 : 10)
            .background {
                if !frameless {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.28))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(liveTint.opacity(urgent ? 0.7 : 0.35), lineWidth: 1)
                        )
                }
            }
            .shadow(color: frameless ? .clear : liveTint.opacity(urgent ? 0.4 : 0.12), radius: urgent ? 10 : 4)
            .opacity(stageOpacity)
        }
    }
}

/// Secondary ahead items (web warn-reel queue) — same kinds as RouteGuard / RadarAlert.
struct EtubuWarnReelView: View {
    let items: [EtubuWarnItem]
    let theme: ClusterTheme
    var vertical: Bool = false

    var body: some View {
        let secondary = Array(items.dropFirst().prefix(vertical ? 2 : 3))
        if !secondary.isEmpty {
            if vertical {
                // Web warn-reel: vertical slots under primary
                VStack(spacing: 4) {
                    ForEach(Array(secondary.enumerated()), id: \.element.id) { idx, item in
                        HStack(spacing: 6) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title)
                                    .font(EtubuClusterFonts.ui(11, weight: .semibold))
                                    .foregroundStyle(theme.primaryText.opacity(idx == 0 ? 0.9 : 0.55))
                                    .lineLimit(1)
                                if !item.distanceLabel.isEmpty {
                                    Text(item.distanceLabel)
                                        .font(EtubuClusterFonts.ui(11, weight: .medium))
                                        .monospacedDigit()
                                        .foregroundStyle(theme.mutedText)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(idx == 0 ? 0.08 : 0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(theme.stroke.opacity(0.8), lineWidth: 1)
                                )
                        )
                        .opacity(idx == 0 ? 0.85 : 0.45)
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(secondary) { item in
                            HStack(spacing: 6) {
                                Image(systemName: EtubuHazardChrome.icon(item.kind))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(EtubuHazardChrome.tint(item.kind, urgent: false, theme: theme))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title)
                                        .font(EtubuClusterFonts.ui(11, weight: .semibold))
                                        .foregroundStyle(theme.primaryText.opacity(0.9))
                                        .lineLimit(1)
                                    if !item.distanceLabel.isEmpty {
                                        Text(item.distanceLabel)
                                            .font(EtubuClusterFonts.ui(11, weight: .medium))
                                            .monospacedDigit()
                                            .foregroundStyle(theme.mutedText)
                                    }
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(theme.surface)
                                    .overlay(Capsule().strokeBorder(theme.stroke, lineWidth: 1))
                            )
                        }
                    }
                }
            }
        }
    }
}

struct EtubuRouteBriefChipsView: View {
    let brief: EtubuRouteBriefSummary
    var compact: Bool = false

    private var chips: [(String, Int, String, Color)] {
        [
            ("camera.metering.spot", brief.radarCount, EtubuClusterL10n.t("routeRadar"), .orange),
            ("mappin.and.ellipse", brief.controlCount, EtubuClusterL10n.t("routeControl"), .purple),
            ("gauge.with.dots.needle.67percent", brief.corridorCount, EtubuClusterL10n.t("radarCorridor"), .orange),
            ("bolt.car.fill", brief.chargeCount, EtubuClusterL10n.t("routeCharge"), .cyan),
            ("cloud.bolt.rain.fill", brief.weatherCount, EtubuClusterL10n.t("routeWeatherShort"), .blue),
        ]
    }

    var body: some View {
        if brief.hasAny {
            VStack(alignment: .leading, spacing: compact ? 6 : 8) {
                FlowChips(items: chips.filter { $0.1 > 0 }, compact: compact)
                if !brief.chargeNames.isEmpty {
                    Text(brief.chargeNames.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(2)
                }
                if !brief.weatherLabels.isEmpty {
                    Text(brief.weatherLabels.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.blue.opacity(0.75))
                        .lineLimit(2)
                }
            }
        }
    }
}

private struct FlowChips: View {
    let items: [(String, Int, String, Color)]
    var compact: Bool

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 4) {
                    Image(systemName: item.0)
                        .font(.system(size: compact ? 9 : 10, weight: .bold))
                    Text("\(item.1)")
                        .font(EtubuClusterFonts.ui(compact ? 11 : 12, weight: .bold))
                        .monospacedDigit()
                    if !compact {
                        Text(item.2)
                            .font(EtubuClusterFonts.ui(10, weight: .semibold))
                    }
                }
                .foregroundStyle(item.3)
                .padding(.horizontal, compact ? 8 : 10)
                .padding(.vertical, compact ? 5 : 6)
                .background(Capsule().fill(item.3.opacity(0.14)))
            }
        }
    }
}

/// Web `avg-speed-panel` — twin of road-warning card (Jul 29 equal panels).
struct EtubuCorridorChipView: View {
    @ObservedObject var warnings: EtubuDriveWarnings
    var theme: ClusterTheme = .aurora
    var compact: Bool = false
    var contentScale: CGFloat = 1

    private var isCorridor: Bool { warnings.corridorActive }
    private var isOver: Bool { warnings.corridorOver }
    private var avg: Int { warnings.corridorAvgKmh }

    private var titleSize: CGFloat { (isCorridor ? 11 : 10) * contentScale }
    private var avgSize: CGFloat {
        // Landscape (compact) +15% on average speed digits
        let base = (isCorridor ? (compact ? 26 : 30) : (compact ? 20 : 24)) * contentScale
        return compact ? base * 1.15 : base
    }
    private var metaSize: CGFloat { 10 * contentScale }

    var body: some View {
        VStack(spacing: compact ? 3 : 5) {
            if isCorridor {
                Text(warnings.corridorLabel.isEmpty
                     ? EtubuClusterL10n.radarCorridor.uppercased()
                     : warnings.corridorLabel.uppercased())
                    .font(EtubuClusterFonts.ui(8 * contentScale, weight: .heavy))
                    .tracking(1.0)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(
                            LinearGradient(
                                colors: [Color(red: 1, green: 0.82, blue: 0.48), Color(red: 1, green: 0.69, blue: 0.13)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    )
                    .foregroundStyle(Color(red: 0.1, green: 0.07, blue: 0.02))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Text(isCorridor ? EtubuClusterL10n.corridorAvg : EtubuClusterL10n.avgSpeed)
                .font(EtubuClusterFonts.ui(titleSize, weight: .semibold))
                .foregroundStyle(isCorridor ? Color(red: 1, green: 0.9, blue: 0.67).opacity(0.9) : theme.mutedText)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                if isOver {
                    TimelineView(.animation(minimumInterval: 1.0 / 8.0, paused: false)) { timeline in
                        let pulse = 0.55 + 0.45 * abs(sin(timeline.date.timeIntervalSinceReferenceDate * 3.2))
                        Text("\(avg)")
                            .font(EtubuClusterFonts.gauge(avgSize))
                            .monospacedDigit()
                            .foregroundStyle(Color(red: 1, green: 0.35, blue: 0.35).opacity(pulse))
                            .minimumScaleFactor(0.55)
                            .lineLimit(1)
                    }
                } else {
                    Text("\(avg)")
                        .font(EtubuClusterFonts.gauge(avgSize))
                        .monospacedDigit()
                        .foregroundStyle(isCorridor ? Color(red: 1, green: 0.88, blue: 0.54) : theme.primaryText)
                        .minimumScaleFactor(0.55)
                        .lineLimit(1)
                }
                Text("km/h")
                    .font(EtubuClusterFonts.ui(9 * contentScale, weight: .medium))
                    .foregroundStyle(theme.mutedText.opacity(0.8))
            }

            if isCorridor {
                HStack(spacing: 6) {
                    if let limit = warnings.corridorLimit {
                        Text("lim \(limit)")
                            .font(EtubuClusterFonts.ui(metaSize, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(theme.secondaryText)
                    }
                    if !warnings.corridorRemainLabel.isEmpty {
                        Text(warnings.corridorRemainLabel)
                            .font(EtubuClusterFonts.ui(metaSize, weight: .medium))
                            .foregroundStyle(theme.mutedText)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                if isOver {
                    TimelineView(.animation(minimumInterval: 1.0 / 8.0, paused: false)) { timeline in
                        let pulse = 0.55 + 0.45 * abs(sin(timeline.date.timeIntervalSinceReferenceDate * 3.2))
                        Text(EtubuClusterL10n.slowDown)
                            .font(EtubuClusterFonts.ui(10 * contentScale, weight: .black))
                            .foregroundStyle(Color.red.opacity(pulse))
                            .lineLimit(1)
                    }
                }
            } else if !warnings.tripDistLabel.isEmpty {
                Text(warnings.tripDistLabel)
                    .font(EtubuClusterFonts.ui(metaSize, weight: .medium))
                    .foregroundStyle(theme.mutedText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else if !warnings.corridorRemainLabel.isEmpty {
                Text(warnings.corridorRemainLabel)
                    .font(EtubuClusterFonts.ui(metaSize, weight: .medium))
                    .foregroundStyle(theme.mutedText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            if !isCorridor {
                Button {
                    EtubuClusterAudioBridge.evalJS("""
                    (function(){
                      try {
                        document.getElementById('avgSpeedReset')?.click?.();
                        if (window.resetTripAvg) window.resetTripAvg();
                      } catch(e) {}
                    })();
                    """)
                } label: {
                    Text(EtubuClusterL10n.t("avgReset"))
                        .font(EtubuClusterFonts.ui(9 * contentScale, weight: .semibold))
                        .foregroundStyle(theme.accent.opacity(0.9))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .modifier(EtubuTwinCardChrome(
            theme: theme,
            stroke: isOver ? Color.red.opacity(0.75) : (isCorridor ? Color.orange.opacity(0.65) : theme.accent.opacity(0.55)),
            warmFill: isCorridor,
            shadowColor: isOver ? Color.red.opacity(0.35) : (isCorridor ? Color.orange.opacity(0.2) : Color.black.opacity(0.32))
        ))
    }
}

/// Twin of avg card — same frame size; kind icon + distance; extras clipped to fit.
struct EtubuRoadWarnTwinView: View {
    @ObservedObject var warnings: EtubuDriveWarnings
    var theme: ClusterTheme
    var compact: Bool = false
    var contentScale: CGFloat = 1

    private var urgent: Bool {
        guard let p = warnings.primary else { return false }
        return p.stage == .critical || p.stage == .near
    }

    private var titleSize: CGFloat { (compact ? 9 : 10) * contentScale }
    private var valueSize: CGFloat { (compact ? 18 : 22) * contentScale }
    private var metaSize: CGFloat { (compact ? 8 : 9) * contentScale }

    var body: some View {
        let tint = EtubuHazardChrome.tint(warnings.primary?.kind ?? "radar", urgent: urgent, theme: theme)
        VStack(alignment: .center, spacing: compact ? 2 : 3) {
            Text(EtubuClusterL10n.roadWarnings.uppercased())
                .font(EtubuClusterFonts.ui(titleSize, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(theme.mutedText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let item = warnings.primary {
                HStack(spacing: 5) {
                    Image(systemName: EtubuHazardChrome.icon(item.kind))
                        .font(.system(size: (compact ? 11 : 13) * contentScale, weight: .bold))
                        .foregroundStyle(tint)
                    Text(EtubuHazardChrome.kicker(item.kind, urgent: urgent))
                        .font(EtubuClusterFonts.ui((compact ? 8 : 9) * contentScale, weight: .heavy))
                        .foregroundStyle(tint.opacity(0.95))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }

                Text(item.distanceLabel.isEmpty ? "—" : item.distanceLabel)
                    .font(EtubuClusterFonts.gauge(valueSize))
                    .monospacedDigit()
                    .foregroundStyle(urgent ? tint : theme.primaryText)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .layoutPriority(3)

                // Alta sığan ek bilgi
                Text(item.title.isEmpty ? "—" : item.title)
                    .font(EtubuClusterFonts.ui(metaSize, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(compact ? 1 : 2)
                    .minimumScaleFactor(0.6)

                if !compact, !item.meta.isEmpty {
                    Text(item.meta)
                        .font(EtubuClusterFonts.ui(metaSize, weight: .medium))
                        .foregroundStyle(theme.mutedText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            } else {
                Text("—")
                    .font(EtubuClusterFonts.gauge(valueSize))
                    .foregroundStyle(theme.mutedText.opacity(0.4))
                Text(EtubuClusterL10n.t("roadClear"))
                    .font(EtubuClusterFonts.ui(metaSize, weight: .medium))
                    .foregroundStyle(theme.mutedText.opacity(0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .modifier(EtubuTwinCardChrome(
            theme: theme,
            stroke: urgent ? tint.opacity(0.8) : theme.accent.opacity(0.55),
            warmFill: false,
            shadowColor: urgent ? tint.opacity(0.22) : Color.black.opacity(0.32)
        ))
    }
}

/// Shared Jul 29 twin-panel chrome — identical frame language for avg + road warnings.
/// Stroke stays outside content clip so full cards never lose top/bottom borders.
private struct EtubuTwinCardChrome: ViewModifier {
    var theme: ClusterTheme
    var stroke: Color
    var warmFill: Bool
    var shadowColor: Color

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        content
            // İçerik taşarsa kes; çerçeve çizgisi overlay’de kalır.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
            .background(
                shape.fill(
                    warmFill
                    ? LinearGradient(
                        colors: [
                            Color(red: 0.22, green: 0.14, blue: 0.02).opacity(0.72),
                            Color(red: 0.11, green: 0.06, blue: 0.01).opacity(0.62),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                      )
                    : LinearGradient(
                        colors: [
                            theme.surface.opacity(0.92),
                            Color.black.opacity(0.34),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                      )
                )
            )
            .overlay(
                shape.strokeBorder(stroke, lineWidth: 1.25)
            )
            .clipShape(shape)
            .shadow(color: shadowColor, radius: 4)
    }
}

/// Regen-only meter (tüketim barı yok).
struct EtubuPowerRegenBarView: View {
    let powerKw: Int?
    var compact: Bool = false
    var theme: ClusterTheme = .aurora
    @State private var displayKw: Double = 0

    private var targetPower: Int {
        let raw = powerKw ?? 0
        return abs(raw) < 4 ? 0 : raw
    }
    private var regenerating: Bool { displayKw < -1 }
    private var fill: CGFloat {
        min(1, CGFloat(abs(displayKw)) / 160.0)
    }
    private var labelColor: Color {
        regenerating ? Color(red: 0.35, green: 0.92, blue: 0.55) : theme.mutedText
    }

    var body: some View {
        // Tüketim (POWER) gösterilmez — yalnızca regen.
        Group {
            if regenerating {
                VStack(alignment: .leading, spacing: compact ? 4 : 6) {
                    HStack {
                        Text("REGEN")
                            .font(EtubuClusterFonts.ui(10, weight: .heavy))
                            .tracking(1)
                            .foregroundStyle(labelColor)
                        Spacer()
                        Text("\(Int(displayKw.rounded())) kW")
                            .font(EtubuClusterFonts.gauge(compact ? 13 : 15))
                            .monospacedDigit()
                            .foregroundStyle(labelColor)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(theme.surface.opacity(0.55))
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.2, green: 0.85, blue: 0.45).opacity(0.95),
                                            Color(red: 0.35, green: 0.95, blue: 0.65).opacity(0.55),
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(4, geo.size.width * fill))
                        }
                    }
                    .frame(height: compact ? 8 : 10)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Regen \(Int(displayKw.rounded())) kilowatt")
            }
        }
        .onAppear { displayKw = Double(targetPower) }
        .onChange(of: targetPower) { _, new in
            withAnimation(.easeInOut(duration: 0.32)) {
                displayKw = Double(new)
            }
        }
    }
}
