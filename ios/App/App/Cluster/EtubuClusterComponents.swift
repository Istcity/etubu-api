import SwiftUI

struct EtubuSpeedDialView: View {
    let kmh: Int
    let gear: String
    let theme: ClusterTheme
    var compact: Bool = false
    /// Optional override — landscape Dynamic Island uses smaller dial to avoid overflow.
    var diameter: CGFloat? = nil
    var powerKw: Int? = nil

    private var dialSize: CGFloat { diameter ?? (compact ? 200 : 280) }

    private var textBoost: CGFloat { 1.22 }
    private var gearBoost: CGFloat { compact ? 0.68 : 0.82 }

    private var speedFont: CGFloat {
        let base: CGFloat = compact
            ? max(72, min(dialSize * 0.34, 104))
            : max(100, min(dialSize * 0.40, 132))
        return base * textBoost * theme.gaugeScale
    }

    private var gearFont: CGFloat {
        let base: CGFloat = compact
            ? max(10, min(dialSize * 0.044, 13.5))
            : max(12, min(dialSize * 0.052, 16))
        return base * gearBoost
    }

    private var unitFont: CGFloat {
        let base: CGFloat = compact
            ? max(10, min(dialSize * 0.050, 15))
            : max(13, min(dialSize * 0.058, 18))
        return base * textBoost
    }

    private var kwFont: CGFloat {
        compact ? max(10, min(dialSize * 0.045, 14)) : max(12, min(dialSize * 0.048, 16))
    }

    private var gearSpacing: CGFloat {
        compact ? max(5, dialSize * 0.026) : max(7, dialSize * 0.034)
    }
    private var gearBarWidth: CGFloat {
        compact ? max(6, dialSize * 0.028) : max(8, dialSize * 0.034)
    }
    private var speedProgress: CGFloat { min(1, CGFloat(max(0, kmh)) / 180) }
    private var power: Int { powerKw ?? 0 }
    private var powerFill: CGFloat { min(1, CGFloat(abs(power)) / 160) }

    /// Clearance from the visible outer stroke only (no invisible clip circle).
    private var ringClearance: CGFloat {
        guard compact else { return dialSize * 0.06 }
        return theme.ringLineWidth(for: dialSize) * 2.2 + dialSize * 0.04
    }

    var body: some View {
        ZStack {
            if compact {
                dialRings
            }

            // Content is NOT circle-masked — only the drawn ring stroke defines the circle.
            VStack(spacing: compact ? max(1, dialSize * 0.008) : 5) {
                gearRow
                Text("\(kmh)")
                    .font(EtubuClusterFonts.gauge(speedFont))
                    .monospacedDigit()
                    .tracking(min(theme.gaugeTracking, 0.8) * 0.06)
                    .foregroundStyle(theme.primaryText)
                    .shadow(color: theme.accent.opacity(0.4), radius: compact ? 8 : 6)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Text("km/h")
                    .font(EtubuClusterFonts.ui(unitFont, weight: .semibold))
                    .foregroundStyle(theme.mutedText)
                    .tracking(min(theme.gaugeTracking, 0.8) * 0.4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if compact {
                    Text(powerKw.map { "\($0) kW" } ?? "— kW")
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
            .padding(.horizontal, ringClearance + dialSize * 0.04)
            .padding(.vertical, ringClearance + dialSize * 0.02)
            .frame(maxWidth: dialSize - ringClearance * 2, maxHeight: dialSize - ringClearance * 2)
        }
        .frame(width: dialSize, height: dialSize)
        // No clipShape(Circle) — that was the invisible cutter
    }

    @ViewBuilder
    private var dialRings: some View {
        let lw = theme.ringLineWidth(for: dialSize)
        ZStack {
            // Single outer track
            Circle()
                .strokeBorder(theme.stroke.opacity(0.40), lineWidth: lw)

            switch theme.dialRingStyle {
            case .thin:
                Circle()
                    .strokeBorder(theme.accent.opacity(0.55 + 0.25 * speedProgress), lineWidth: lw * 1.15)
                    .shadow(color: theme.glow, radius: 8)

            case .neonSweep:
                Circle()
                    .trim(from: 0, to: max(0.04, speedProgress))
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
                    .animation(.easeOut(duration: 0.25), value: speedProgress)

            case .dualGlow:
                // Thicker dual-glow — still ON the same outer ring (no inner concentric clip circle)
                Circle()
                    .strokeBorder(theme.accent.opacity(0.28), lineWidth: lw * 2.1)
                Circle()
                    .trim(from: 0, to: max(0.05, speedProgress))
                    .stroke(theme.accent, style: StrokeStyle(lineWidth: lw * 1.45, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: theme.accent.opacity(0.75), radius: 12)

            case .dashed:
                Circle()
                    .strokeBorder(theme.accent.opacity(0.7), style: StrokeStyle(lineWidth: lw * 1.2, dash: [7, 5]))
                Circle()
                    .trim(from: 0, to: max(0.03, speedProgress))
                    .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: lw * 0.85, lineCap: .round))
                    .rotationEffect(.degrees(-90))

            case .plasmaRibbon:
                Circle()
                    .trim(from: 0, to: max(0.06, speedProgress))
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
                    .rotationEffect(.degrees(-90 + Double(kmh % 360) * 0.15))
                    .shadow(color: theme.glow, radius: 12)
            }

            // Bipolar regen / drive meter on the ring (power-bar behaviour)
            bipolarPowerRing(lineWidth: lw)
        }
        .frame(width: dialSize, height: dialSize)
        .allowsHitTesting(false)
    }

    /// Mirrors `EtubuPowerRegenBarView`: green = regen (left), warm = drive (right).
    private func bipolarPowerRing(lineWidth: CGFloat) -> some View {
        let regen = power < -1
        let drive = power > 1
        let fill = powerFill
        let track = lineWidth * 1.35
        return ZStack {
            // Neutral track along lower half
            Circle()
                .trim(from: 0.12, to: 0.88)
                .stroke(Color.white.opacity(0.10), style: StrokeStyle(lineWidth: track, lineCap: .round))
                .rotationEffect(.degrees(90))

            // Regen fills left side of lower arc (toward 0.12 ← mid)
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

            // Drive fills right side of lower arc (mid → 0.88)
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
        .animation(.easeOut(duration: 0.2), value: power)
    }

    private var gearRow: some View {
        HStack(spacing: gearSpacing) {
            ForEach(["P", "R", "N", "D"], id: \.self) { g in
                VStack(spacing: compact ? 1 : 2) {
                    Text(g)
                        .font(EtubuClusterFonts.gauge(gearFont, weight: .bold))
                        .foregroundStyle(g == gear ? theme.accent : theme.mutedText)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Capsule()
                        .fill(g == gear ? theme.accent : Color.clear)
                        .frame(width: gearBarWidth, height: compact ? 1.5 : 2)
                }
            }
        }
    }
}

enum EtubuHazardChrome {
    static func icon(_ kind: String) -> String {
        switch kind {
        case "corridor": return "gauge.with.dots.needle.67percent"
        case "charge": return "bolt.car.fill"
        case "weather": return "cloud.bolt.rain.fill"
        case "control": return "mappin.and.ellipse"
        default: return "camera.metering.spot"
        }
    }

    static func kicker(_ kind: String, urgent: Bool) -> String {
        switch kind {
        case "corridor": return "HIZ KORİDORU"
        case "charge": return "ŞARJ"
        case "weather": return "HAVA"
        case "control": return "KONTROL"
        default: return urgent ? "KRİTİK NOKTA" : "RADAR"
        }
    }

    static func tint(_ kind: String, urgent: Bool, theme: ClusterTheme) -> Color {
        switch kind {
        case "corridor": return urgent ? .orange : Color.orange.opacity(0.9)
        case "charge": return Color.cyan
        case "weather": return Color.blue
        case "control": return Color.purple.opacity(0.9)
        default: return urgent ? .orange : theme.accent
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
        HStack(spacing: 12) {
            Image(systemName: EtubuHazardChrome.icon(item.kind))
                .font(.title3.weight(.bold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(EtubuHazardChrome.kicker(item.kind, urgent: urgent))
                    .font(EtubuClusterFonts.ui(10, weight: .heavy))
                    .tracking(1)
                    .foregroundStyle(tint)
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
                        .strokeBorder(tint.opacity(0.7), lineWidth: 1.2)
                )
        )
        .shadow(color: tint.opacity(0.35), radius: urgent ? 12 : 6)
        .scaleEffect(item.stage == .critical ? 1.02 : 1)
        .animation(item.stage == .critical ? .easeInOut(duration: 0.55).repeatForever(autoreverses: true) : .default, value: item.stage)
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
        VStack(spacing: 4) {
            Text(item.title.isEmpty ? EtubuHazardChrome.kicker(item.kind, urgent: urgent) : item.title)
                .font(EtubuClusterFonts.ui((compact ? 11 : 12) * contentScale, weight: .bold))
                .foregroundStyle(tint)
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
                            .strokeBorder(tint.opacity(urgent ? 0.65 : 0.35), lineWidth: 1)
                    )
            }
        }
        .shadow(color: frameless ? .clear : tint.opacity(urgent ? 0.35 : 0.12), radius: urgent ? 10 : 4)
        .opacity(stageOpacity)
        .scaleEffect(item.stage == .critical ? 1.03 : 1)
        .animation(item.stage == .critical ? .easeInOut(duration: 0.55).repeatForever(autoreverses: true) : .default, value: item.stage)
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
            ("camera.metering.spot", brief.radarCount, "Radar", .orange),
            ("mappin.and.ellipse", brief.controlCount, "Kontrol", .purple),
            ("gauge.with.dots.needle.67percent", brief.corridorCount, "Koridor", .orange),
            ("bolt.car.fill", brief.chargeCount, "Şarj", .cyan),
            ("cloud.bolt.rain.fill", brief.weatherCount, "Hava", .blue),
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
        (isCorridor ? (compact ? 26 : 30) : (compact ? 20 : 24)) * contentScale
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
                Text("\(avg)")
                    .font(EtubuClusterFonts.gauge(avgSize))
                    .monospacedDigit()
                    .foregroundStyle(isOver ? Color(red: 1, green: 0.6, blue: 0.6) : (isCorridor ? Color(red: 1, green: 0.88, blue: 0.54) : theme.primaryText))
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
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
                    Text(EtubuClusterL10n.slowDown)
                        .font(EtubuClusterFonts.ui(10 * contentScale, weight: .black))
                        .foregroundStyle(.red)
                        .lineLimit(1)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .modifier(EtubuTwinCardChrome(
            theme: theme,
            stroke: isOver ? Color.red.opacity(0.65) : (isCorridor ? Color.orange.opacity(0.55) : theme.accent.opacity(0.38)),
            warmFill: isCorridor,
            shadowColor: isOver ? Color.red.opacity(0.35) : (isCorridor ? Color.orange.opacity(0.2) : Color.black.opacity(0.32))
        ))
    }
}

/// Twin of avg card — road / radar / corridor alerts under one title (Jul 29).
struct EtubuRoadWarnTwinView: View {
    @ObservedObject var warnings: EtubuDriveWarnings
    var theme: ClusterTheme
    var compact: Bool = false
    var contentScale: CGFloat = 1

    private var urgent: Bool {
        guard let p = warnings.primary else { return false }
        return p.stage == .critical || p.stage == .near
    }

    var body: some View {
        let secondary = Array(warnings.queue.dropFirst().prefix(compact ? 1 : 2))
        VStack(alignment: .center, spacing: compact ? 3 : 4) {
            Text(EtubuClusterL10n.roadWarnings.uppercased())
                .font(EtubuClusterFonts.ui(9 * contentScale, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(theme.mutedText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let item = warnings.primary {
                let tint = EtubuHazardChrome.tint(item.kind, urgent: urgent, theme: theme)
                Text(item.title.isEmpty ? EtubuHazardChrome.kicker(item.kind, urgent: urgent) : item.title)
                    .font(EtubuClusterFonts.ui(11 * contentScale, weight: .bold))
                    .foregroundStyle(tint)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.65)
                Text(item.distanceLabel.isEmpty ? "—" : item.distanceLabel)
                    .font(EtubuClusterFonts.gauge((compact ? 20 : 24) * contentScale))
                    .monospacedDigit()
                    .foregroundStyle(theme.primaryText)
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                if !item.meta.isEmpty {
                    Text(item.meta)
                        .font(EtubuClusterFonts.ui(9 * contentScale, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                ForEach(Array(secondary.enumerated()), id: \.element.id) { _, next in
                    HStack(spacing: 4) {
                        Text(next.title)
                            .font(EtubuClusterFonts.ui(9 * contentScale, weight: .semibold))
                            .foregroundStyle(theme.primaryText.opacity(0.7))
                            .lineLimit(1)
                        if !next.distanceLabel.isEmpty {
                            Text(next.distanceLabel)
                                .font(EtubuClusterFonts.ui(9 * contentScale, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(theme.mutedText)
                                .lineLimit(1)
                        }
                    }
                    .minimumScaleFactor(0.65)
                }
            } else {
                Text("—")
                    .font(EtubuClusterFonts.gauge(18 * contentScale))
                    .foregroundStyle(theme.mutedText.opacity(0.4))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .modifier(EtubuTwinCardChrome(
            theme: theme,
            stroke: urgent ? Color.orange.opacity(0.55) : theme.accent.opacity(0.38),
            warmFill: false,
            shadowColor: urgent ? Color.orange.opacity(0.22) : Color.black.opacity(0.32)
        ))
    }
}

/// Shared Jul 29 twin-panel chrome — identical frame language for avg + road warnings.
private struct EtubuTwinCardChrome: ViewModifier {
    var theme: ClusterTheme
    var stroke: Color
    var warmFill: Bool
    var shadowColor: Color

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
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
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(stroke, lineWidth: 1)
                    )
            )
            .shadow(color: shadowColor, radius: 8)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Bipolar power meter: green left = regen (negative kW), warm right = drive (positive).
/// Colors follow active `ClusterTheme`.
struct EtubuPowerRegenBarView: View {
    let powerKw: Int?
    var compact: Bool = false
    var theme: ClusterTheme = .aurora

    private var power: Int { powerKw ?? 0 }
    private var regenerating: Bool { power < -1 }
    private var accelerating: Bool { power > 1 }

    private var fill: CGFloat {
        min(1, CGFloat(abs(power)) / 160.0)
    }

    private var labelColor: Color {
        if regenerating { return Color(red: 0.35, green: 0.92, blue: 0.55) }
        if accelerating { return theme.accent }
        return theme.mutedText
    }

    private var driveColors: [Color] {
        [theme.accent.opacity(0.45), theme.accent, Color.yellow.opacity(0.85)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            HStack {
                Text(regenerating ? "REGEN" : "POWER")
                    .font(EtubuClusterFonts.ui(10, weight: .heavy))
                    .tracking(1)
                    .foregroundStyle(labelColor)
                Spacer()
                Text(powerLabel)
                    .font(EtubuClusterFonts.gauge(compact ? 13 : 15))
                    .monospacedDigit()
                    .foregroundStyle(labelColor)
                    .contentTransition(.numericText())
            }

            GeometryReader { geo in
                let mid = geo.size.width / 2
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
                        .frame(width: max(2, mid * (regenerating ? fill : 0)))
                        .offset(x: mid - max(2, mid * (regenerating ? fill : 0)))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: driveColors,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(2, mid * (accelerating ? fill : 0)))
                        .offset(x: mid)
                    Rectangle()
                        .fill(Color.white.opacity(0.55))
                        .frame(width: 2, height: compact ? 10 : 12)
                        .position(x: mid, y: geo.size.height / 2)
                }
            }
            .frame(height: compact ? 8 : 10)
        }
        .padding(.horizontal, compact ? 10 : 12)
        .padding(.vertical, compact ? 8 : 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.canvas.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(labelColor.opacity(regenerating || accelerating ? 0.4 : 0.14), lineWidth: 1)
                )
        )
        .animation(.easeOut(duration: 0.2), value: power)
    }

    private var powerLabel: String {
        if power > 0 { return "+\(power) kW" }
        if power < 0 { return "\(power) kW" }
        return "0 kW"
    }
}
