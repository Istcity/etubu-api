import SwiftUI

/// ETUBU visual themes (aligned with `js/scene-webgl.js` MODE_HUE).
enum ClusterTheme: String, CaseIterable, Identifiable {
    case aurora, plasma, redline, cyberLime, electricIce, solarFlare
    case neon, violetStorm, deepOcean, midnight, tunnel, warp

    var id: String { rawValue }

    var title: String {
        EtubuClusterL10n.t("themeName.\(rawValue)")
    }

    /// Scene hue degrees from ETUBU web themes.
    var hue: Double {
        switch self {
        case .aurora: return 185
        case .plasma: return 295
        case .redline: return 358
        case .cyberLime: return 92
        case .electricIce: return 188
        case .solarFlare: return 36
        case .neon: return 318
        case .violetStorm: return 268
        case .deepOcean: return 204
        case .midnight: return 210
        case .tunnel: return 165
        case .warp: return 255
        }
    }

    private var h: Double { hue / 360 }

    var accent: Color {
        Color(hue: h, saturation: 0.85, brightness: 0.95)
    }

    var accentSoft: Color {
        Color(hue: h, saturation: 0.55, brightness: 0.7)
    }

    /// Deep tinted base — entire cluster reads as this theme, not flat black.
    var canvas: Color {
        Color(hue: h, saturation: 0.55, brightness: 0.07)
    }

    var canvasHigh: Color {
        Color(hue: h, saturation: 0.5, brightness: 0.14)
    }

    var surface: Color {
        Color(hue: h, saturation: 0.35, brightness: 0.16).opacity(0.72)
    }

    var primaryText: Color { .white }

    var secondaryText: Color {
        Color(hue: h, saturation: 0.12, brightness: 0.78).opacity(0.72)
    }

    var mutedText: Color {
        Color(hue: h, saturation: 0.1, brightness: 0.7).opacity(0.45)
    }

    var stroke: Color {
        accent.opacity(0.28)
    }

    var glow: Color {
        accent.opacity(0.35)
    }

    /// Full-bleed atmospheric gradient.
    var canvasGradient: [Color] {
        [
            canvasHigh,
            canvas,
            Color(hue: h, saturation: 0.4, brightness: 0.04),
            Color.black,
        ]
    }

    /// Portrait / landscape edge wash.
    var washColors: [Color] {
        switch self {
        case .solarFlare, .redline, .neon:
            return [
                Color(hue: h, saturation: 0.85, brightness: 0.35),
                Color(hue: ((hue + 40).truncatingRemainder(dividingBy: 360)) / 360, saturation: 0.9, brightness: 0.55),
            ]
        case .aurora, .electricIce, .deepOcean, .midnight, .tunnel:
            return [
                Color(hue: h, saturation: 0.7, brightness: 0.22),
                Color(hue: h, saturation: 0.8, brightness: 0.45),
            ]
        default:
            return [
                Color(hue: h, saturation: 0.75, brightness: 0.28),
                Color(hue: ((hue + 50).truncatingRemainder(dividingBy: 360)) / 360, saturation: 0.85, brightness: 0.5),
            ]
        }
    }

    var background: [Color] { canvasGradient }

    /// Letter-spacing for gauge labels — slightly tighter on “hot” themes.
    /// Font family for speed gauge / numbers — PostScript names that resolve on iOS.
    var gaugeFont: String {
        switch self {
        case .aurora: return "Orbitron-Bold"
        case .plasma: return "Menlo-Bold"
        case .redline: return "DINCondensed-Bold"
        case .cyberLime: return "CourierNewPS-BoldMT"
        case .electricIce: return "AvenirNext-Bold"
        case .solarFlare: return "DINAlternate-Bold"
        case .neon: return "AvenirNextCondensed-Bold"
        case .violetStorm: return "Futura-Bold"
        case .deepOcean: return "GillSans-Bold"
        case .midnight: return "HelveticaNeue-Bold"
        case .tunnel: return "CourierNewPS-BoldMT"
        case .warp: return "Menlo-Bold"
        }
    }

    /// Font family for UI labels, nav column, cards.
    var uiFont: String {
        switch self {
        case .aurora: return "DMSans-Regular"
        case .plasma: return "Menlo-Regular"
        case .redline: return "AvenirNext-Medium"
        case .cyberLime: return "CourierNewPSMT"
        case .electricIce: return "AvenirNext-Regular"
        case .solarFlare: return "AvenirNext-DemiBold"
        case .neon: return "AvenirNextCondensed-Medium"
        case .violetStorm: return "Futura-Medium"
        case .deepOcean: return "GillSans"
        case .midnight: return "DMSans-Regular"
        case .tunnel: return "CourierNewPSMT"
        case .warp: return "Menlo-Regular"
        }
    }

    /// System design fallback when family missing — shapes typography character.
    var gaugeDesign: Font.Design {
        switch self {
        case .aurora, .electricIce, .deepOcean: return .rounded
        case .plasma, .warp, .cyberLime, .tunnel: return .monospaced
        case .redline, .solarFlare, .neon: return .default
        case .violetStorm, .midnight: return .serif
        }
    }

    var uiDesign: Font.Design {
        switch self {
        case .aurora, .midnight, .electricIce: return .default
        case .plasma, .warp, .cyberLime, .tunnel: return .monospaced
        case .redline, .solarFlare, .neon: return .rounded
        case .violetStorm, .deepOcean: return .serif
        }
    }

    var gaugeWeight: Font.Weight {
        switch self {
        case .redline, .neon, .solarFlare: return .black
        case .cyberLime, .tunnel, .warp: return .bold
        case .plasma, .violetStorm: return .heavy
        default: return .bold
        }
    }

    var gaugeTracking: CGFloat {
        switch self {
        case .redline, .solarFlare: return 0.4
        case .neon: return 0.2
        case .cyberLime, .tunnel: return 1.6
        case .plasma, .violetStorm, .warp: return 0.9
        case .midnight, .deepOcean: return 1.2
        default: return 1.0
        }
    }

    /// Relative gauge digit scale vs baseline (shape feel: condensed vs expansive).
    var gaugeScale: CGFloat {
        switch self {
        case .neon, .redline: return 1.08          // condensed tall
        case .cyberLime, .tunnel: return 0.94      // mono compact
        case .plasma, .warp: return 0.97
        case .solarFlare: return 1.05
        default: return 1.0
        }
    }

    /// Landscape dial ring personality.
    enum DialRingStyle: Equatable {
        case thin
        case neonSweep      // progressing neon bar
        case dualGlow
        case dashed
        case plasmaRibbon
    }

    var dialRingStyle: DialRingStyle {
        switch self {
        case .neon, .cyberLime, .warp: return .neonSweep
        case .redline, .solarFlare: return .dualGlow
        case .plasma, .violetStorm: return .plasmaRibbon
        case .tunnel: return .dashed
        case .aurora, .electricIce, .deepOcean, .midnight: return .thin
        }
    }

    /// Outer ring stroke thickness — some themes run thicker for presence.
    func ringLineWidth(for dialSize: CGFloat) -> CGFloat {
        let base = max(2.4, dialSize * 0.020)
        switch dialRingStyle {
        case .neonSweep, .plasmaRibbon: return base * 1.45
        case .dualGlow: return base * 1.55
        case .dashed: return base * 1.25
        case .thin: return base * 1.15
        }
    }

    /// Power arc on landscape dial for every theme (portrait uses the bar instead).
    var dialShowsPowerArc: Bool { true }

    /// Landscape omits the separate power bar — kW lives on the dial.
    var prefersRingPower: Bool { true }

    /// Key expected by web `Scene.setMode`.
    var webKey: String {
        switch self {
        case .cyberLime: return "cyber-lime"
        case .electricIce: return "electric-ice"
        case .solarFlare: return "solar-flare"
        case .violetStorm: return "violet-storm"
        case .deepOcean: return "deep-ocean"
        case .midnight: return "aurora"
        default: return rawValue
        }
    }

    static var stored: ClusterTheme {
        get {
            if let raw = UserDefaults.standard.string(forKey: "etubu.cluster.theme"),
               let t = ClusterTheme(rawValue: raw) {
                return t
            }
            return .aurora
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "etubu.cluster.theme") }
    }
}

private struct ClusterThemeKey: EnvironmentKey {
    static let defaultValue: ClusterTheme = .aurora
}

extension EnvironmentValues {
    var clusterTheme: ClusterTheme {
        get { self[ClusterThemeKey.self] }
        set { self[ClusterThemeKey.self] = newValue }
    }
}

/// Full-screen theme atmosphere (call once behind cluster chrome).
struct ClusterThemeBackdrop: View {
    let theme: ClusterTheme
    var landscape: Bool = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: theme.canvasGradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [theme.accent.opacity(0.32), .clear],
                center: landscape ? .trailing : .topTrailing,
                startRadius: 20,
                endRadius: landscape ? 520 : 420
            )

            RadialGradient(
                colors: [theme.washColors.last?.opacity(0.55) ?? theme.glow, .clear],
                center: landscape ? .leading : .bottom,
                startRadius: 10,
                endRadius: landscape ? 480 : 360
            )

            LinearGradient(
                colors: [
                    theme.accent.opacity(0.12),
                    .clear,
                    theme.accentSoft.opacity(0.1),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.plusLighter)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
