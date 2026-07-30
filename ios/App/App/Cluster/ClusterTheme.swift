import SwiftUI

/// ETUBU visual themes (aligned with `js/scene-webgl.js` MODE_HUE).
enum ClusterTheme: String, CaseIterable, Identifiable {
    case aurora, plasma, redline, cyberLime, electricIce, solarFlare
    case neon, violetStorm, deepOcean, midnight, tunnel, warp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aurora: return "Aurora"
        case .plasma: return "Plasma"
        case .redline: return "Redline"
        case .cyberLime: return "Cyber Lime"
        case .electricIce: return "Electric Ice"
        case .solarFlare: return "Solar Flare"
        case .neon: return "Neon"
        case .violetStorm: return "Violet Storm"
        case .deepOcean: return "Deep Ocean"
        case .midnight: return "Midnight"
        case .tunnel: return "Tunnel"
        case .warp: return "Warp"
        }
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
    var gaugeTracking: CGFloat {
        switch self {
        case .redline, .solarFlare, .neon: return 0.6
        case .cyberLime, .tunnel: return 1.4
        default: return 1.0
        }
    }

    /// Gauge / UI font families — currently uniform across themes.
    var gaugeFont: String { "Orbitron" }
    var uiFont: String { "DM Sans" }

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
