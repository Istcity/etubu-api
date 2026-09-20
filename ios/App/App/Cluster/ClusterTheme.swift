import SwiftUI

/// ETUBU visual themes (aligned with `js/scene-webgl.js` MODE_HUE).
enum ClusterTheme: String, CaseIterable, Identifiable {
    case tesla, aurora, plasma, redline, cyberLime, electricIce, solarFlare
    case neon, violetStorm, deepOcean, midnight, tunnel, warp
    /// Model S Plaid 0–100 launch screen — yellow → red heat with acceleration.
    case plaidBoost
    /// Dinamik hava durumu ve açık gökyüzü teması
    case weatherSky
    /// Navigasyon ve haritayı ön plana çıkaran HUD teması
    case mapFocus
    /// Apple MapKit 3D Binalar, Yeryüzü Yükseltisi ve Kokpit Perspektifi Teması
    case map3D
    /// Siber fırtına ve şimşek teması
    case cyberStorm
    /// Çöl kumu ve gün batımı teması
    case desertDune
    /// Sadece 2 kadran ve zifiri siyah zemin (OLED / Stealth)
    case stealthOled

    var id: String { rawValue }

    var title: String {
        EtubuClusterL10n.t("themeName.\(rawValue)")
    }

    /// Ayarlar ızgarası — tek şiirsel ad (Duman, Işık Hüzmesi…). Paylaşılan efektte benzersiz kalır.
    var pickerTitle: String {
        switch self {
        case .tesla: return EtubuCutoutFX.duman.title
        case .midnight, .plaidBoost, .weatherSky, .mapFocus, .map3D, .cyberStorm, .desertDune, .stealthOled: return title
        default: return EtubuCutoutFX.forTheme(self).title
        }
    }

    /// Scene hue degrees from ETUBU web themes.
    var hue: Double {
        switch self {
        case .tesla, .stealthOled: return 0
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
        case .plaidBoost: return 28
        case .weatherSky: return 202
        case .mapFocus: return 188
        case .map3D: return 200
        case .cyberStorm: return 275
        case .desertDune: return 32
        }
    }

    private var h: Double { hue / 360 }

    var accent: Color {
        switch self {
        case .tesla: return Color(red: 0.92, green: 0.22, blue: 0.22) // Tesla red
        case .plaidBoost: return Color(red: 1.0, green: 0.42, blue: 0.05)
        case .stealthOled: return Color(red: 0.92, green: 0.94, blue: 0.98)
        default: return Color(hue: h, saturation: 0.85, brightness: 0.95)
        }
    }

    /// TPMS araç kontur rengi — dolgu yok, tema aksanı / yumuşak vurgu.
    var tpmsCarStroke: Color {
        switch self {
        case .tesla, .stealthOled:
            return Color.white.opacity(0.82)
        case .plaidBoost:
            return Color(red: 1.0, green: 0.78, blue: 0.35).opacity(0.9)
        default:
            return accent.opacity(0.88)
        }
    }

    /// Eski dolgu API’si — kontur rengine yönlendir.
    var tpmsCarFill: Color { tpmsCarStroke }

    /// TPMS lastik — gövdeden daha koyu (outline modunda kullanılmıyor).
    var tpmsTireFill: Color {
        Color.black.opacity(0.88)
    }

    var accentSoft: Color {
        switch self {
        case .tesla: return Color(white: 0.72)
        case .plaidBoost: return Color(red: 1.0, green: 0.85, blue: 0.25)
        case .stealthOled: return Color(white: 0.60)
        default: return Color(hue: h, saturation: 0.55, brightness: 0.7)
        }
    }

    /// Deep tinted base — entire cluster reads as this theme, not flat black.
    var canvas: Color {
        switch self {
        case .tesla: return Color(red: 0.04, green: 0.04, blue: 0.045)
        case .plaidBoost: return Color(red: 0.06, green: 0.03, blue: 0.01)
        case .stealthOled: return Color.black
        default: return Color(hue: h, saturation: 0.55, brightness: 0.07)
        }
    }

    var canvasHigh: Color {
        switch self {
        case .tesla: return Color(red: 0.10, green: 0.10, blue: 0.11)
        case .plaidBoost: return Color(red: 0.18, green: 0.08, blue: 0.02)
        case .stealthOled: return Color.black
        default: return Color(hue: h, saturation: 0.5, brightness: 0.14)
        }
    }

    var surface: Color {
        switch self {
        case .tesla: return Color.white.opacity(0.06)
        case .plaidBoost: return Color(red: 1.0, green: 0.35, blue: 0.05).opacity(0.12)
        case .stealthOled: return Color.black
        default: return Color(hue: h, saturation: 0.35, brightness: 0.16).opacity(0.72)
        }
    }

    var primaryText: Color { .white }

    var secondaryText: Color {
        switch self {
        case .tesla, .stealthOled: return Color.white.opacity(0.70)
        case .plaidBoost: return Color(red: 1.0, green: 0.9, blue: 0.7).opacity(0.75)
        default: return Color(hue: h, saturation: 0.12, brightness: 0.78).opacity(0.72)
        }
    }

    var mutedText: Color {
        switch self {
        case .tesla, .stealthOled: return Color.white.opacity(0.42)
        case .plaidBoost: return Color(red: 1.0, green: 0.75, blue: 0.4).opacity(0.45)
        default: return Color(hue: h, saturation: 0.1, brightness: 0.7).opacity(0.45)
        }
    }

    /// Landscape right column over OSM/satellite — opaque ivory vs green/beige ground.
    var mapHudText: Color { Color(red: 1.0, green: 0.97, blue: 0.82) }
    var mapHudMuted: Color { Color(red: 0.78, green: 0.90, blue: 0.62) }
    var mapHudFill: Color { Color.black.opacity(0.64) }

    var stroke: Color {
        switch self {
        case .tesla, .stealthOled: return Color.white.opacity(0.18)
        case .plaidBoost: return Color(red: 1.0, green: 0.55, blue: 0.1).opacity(0.35)
        default: return accent.opacity(0.28)
        }
    }

    var glow: Color {
        switch self {
        case .tesla: return accent.opacity(0.28)
        case .plaidBoost: return Color.orange.opacity(0.45)
        case .stealthOled: return Color.clear
        default: return accent.opacity(0.35)
        }
    }

    /// Full-bleed atmospheric gradient.
    var canvasGradient: [Color] {
        switch self {
        case .stealthOled:
            return [Color.black, Color.black]
        case .tesla:
            return [
                Color(red: 0.12, green: 0.12, blue: 0.13),
                Color(red: 0.05, green: 0.05, blue: 0.055),
                Color(red: 0.02, green: 0.02, blue: 0.025),
                Color.black,
            ]
        case .plaidBoost:
            return [
                Color(red: 0.22, green: 0.10, blue: 0.02),
                Color(red: 0.08, green: 0.03, blue: 0.01),
                Color(red: 0.03, green: 0.01, blue: 0.0),
                Color.black,
            ]
        default:
            return [
                canvasHigh,
                canvas,
                Color(hue: h, saturation: 0.4, brightness: 0.04),
                Color.black,
            ]
        }
    }

    /// Portrait / landscape edge wash.
    var washColors: [Color] {
        switch self {
        case .stealthOled:
            return [Color.clear, Color.clear]
        case .tesla:
            return [Color.white.opacity(0.12), accent.opacity(0.35)]
        case .plaidBoost:
            return [
                Color(red: 1.0, green: 0.9, blue: 0.2),
                Color(red: 1.0, green: 0.35, blue: 0.05),
                Color(red: 0.85, green: 0.05, blue: 0.05),
            ]
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

    /// Font family for speed gauge / numbers — PostScript names that resolve on iOS.
    var gaugeFont: String {
        switch self {
        case .tesla, .stealthOled: return "HelveticaNeue-Bold"
        case .aurora: return "Orbitron-Bold"
        case .plasma, .cyberStorm: return "Menlo-Bold"
        case .redline: return "DINCondensed-Bold"
        case .cyberLime: return "CourierNewPS-BoldMT"
        case .electricIce: return "AvenirNext-Bold"
        case .solarFlare, .plaidBoost, .desertDune: return "DINAlternate-Bold"
        case .neon: return "AvenirNextCondensed-Bold"
        case .violetStorm: return "Futura-Bold"
        case .deepOcean: return "GillSans-Bold"
        case .midnight: return "HelveticaNeue-Bold"
        case .tunnel: return "CourierNewPS-BoldMT"
        case .warp: return "Menlo-Bold"
        case .weatherSky: return "AvenirNext-Bold"
        case .mapFocus, .map3D: return "Orbitron-Bold"
        }
    }

    /// Font family for UI labels, nav column, cards.
    var uiFont: String {
        switch self {
        case .tesla, .stealthOled: return "HelveticaNeue"
        case .aurora, .midnight, .weatherSky, .mapFocus, .map3D: return "DMSans-Regular"
        case .plasma, .warp, .cyberLime, .tunnel, .cyberStorm: return "Menlo-Regular"
        case .redline, .desertDune: return "AvenirNext-Medium"
        case .electricIce: return "AvenirNext-Regular"
        case .solarFlare, .plaidBoost: return "AvenirNext-DemiBold"
        case .neon: return "AvenirNextCondensed-Medium"
        case .violetStorm: return "Futura-Medium"
        case .deepOcean: return "GillSans"
        }
    }

    /// System design fallback when family missing — shapes typography character.
    var gaugeDesign: Font.Design {
        switch self {
        case .tesla, .aurora, .electricIce, .deepOcean, .weatherSky: return .rounded
        case .plasma, .warp, .cyberLime, .tunnel, .mapFocus, .map3D, .cyberStorm: return .monospaced
        case .redline, .solarFlare, .neon, .plaidBoost, .desertDune, .stealthOled: return .default
        case .violetStorm, .midnight: return .serif
        }
    }

    var uiDesign: Font.Design {
        switch self {
        case .tesla, .aurora, .midnight, .electricIce, .mapFocus, .map3D, .stealthOled: return .default
        case .plasma, .warp, .cyberLime, .tunnel, .cyberStorm: return .monospaced
        case .redline, .solarFlare, .neon, .plaidBoost, .weatherSky, .desertDune: return .rounded
        case .violetStorm, .deepOcean: return .serif
        }
    }

    var gaugeWeight: Font.Weight {
        switch self {
        case .tesla, .stealthOled: return .semibold
        case .redline, .neon, .solarFlare, .plaidBoost: return .black
        case .cyberLime, .tunnel, .warp: return .bold
        case .plasma, .violetStorm: return .heavy
        default: return .bold
        }
    }

    var gaugeTracking: CGFloat {
        switch self {
        case .tesla, .stealthOled: return 0.15
        case .redline, .solarFlare, .plaidBoost: return 0.4
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
        case .tesla, .stealthOled: return 1.06
        case .neon, .redline, .plaidBoost: return 1.08
        case .cyberLime, .tunnel: return 0.94
        case .plasma, .warp: return 0.97
        case .solarFlare: return 1.05
        default: return 1.0
        }
    }

    /// Landscape dial ring personality.
    enum DialRingStyle: Equatable {
        case thin
        case neonSweep
        case dualGlow
        case dashed
        case plasmaRibbon
        case plaidHeat
    }

    var dialRingStyle: DialRingStyle {
        switch self {
        case .tesla, .stealthOled: return .thin
        case .neon, .cyberLime, .warp, .mapFocus, .map3D: return .neonSweep
        case .redline, .solarFlare, .desertDune: return .dualGlow
        case .plasma, .violetStorm, .cyberStorm: return .plasmaRibbon
        case .tunnel: return .dashed
        case .plaidBoost: return .plaidHeat
        case .aurora, .electricIce, .deepOcean, .midnight, .weatherSky: return .thin
        }
    }

    /// Outer ring stroke thickness — some themes run thicker for presence.
    func ringLineWidth(for dialSize: CGFloat) -> CGFloat {
        let base = max(2.4, dialSize * 0.020)
        switch dialRingStyle {
        case .neonSweep, .plasmaRibbon, .plaidHeat: return base * 1.45
        case .dualGlow: return base * 1.55
        case .dashed: return base * 1.25
        case .thin: return base * 1.15
        }
    }

    /// Outward bloom of stroke + glow so landscape parents don't clip the ring.
    func ringBloom(for dialSize: CGFloat) -> CGFloat {
        let lw = ringLineWidth(for: dialSize)
        switch dialRingStyle {
        case .neonSweep: return lw * 0.80 + 12
        case .dualGlow: return lw * 1.10 + 14
        case .plasmaRibbon: return lw * 0.90 + 14
        case .plaidHeat: return lw * 0.95 + 16
        case .dashed: return lw * 0.62 + 4
        case .thin: return lw * 0.60 + 10
        }
    }

    /// Power arc on landscape dial for every theme (portrait uses the bar instead).
    var dialShowsPowerArc: Bool { true }

    /// Landscape omits the separate power bar — kW lives on the dial.
    var prefersRingPower: Bool { true }

    /// Key expected by web `Scene.setMode` — unique per theme (no visual-mode collisions).
    var webKey: String {
        switch self {
        case .cyberLime: return "cyber-lime"
        case .electricIce: return "electric-ice"
        case .solarFlare: return "solar-flare"
        case .plaidBoost: return "plaid-boost"
        case .violetStorm: return "violet-storm"
        case .deepOcean: return "deep-ocean"
        case .tesla: return "tesla"
        case .midnight: return "midnight"
        case .weatherSky: return "weather-sky"
        case .mapFocus: return "map-focus"
        case .map3D: return "map-3d"
        case .cyberStorm: return "cyber-storm"
        case .desertDune: return "desert-dune"
        case .stealthOled: return "stealth-oled"
        default: return rawValue
        }
    }

    /// RevHeadz modeli: tema = bir ses paketi (yüzlerce ses yok).
    /// Anahtar AudioEngine / NativeDriveAudio profiline çözülür.
    var driveVoiceKey: String { rawValue }

    /// EV karakter bankası — soft / sport / boost (paylaşılan WAV, farklı yük eğrisi).
    var driveBasePack: String {
        switch self {
        case .tesla, .midnight, .deepOcean, .tunnel, .weatherSky, .stealthOled:
            return "calm-ev"
        case .aurora, .electricIce, .cyberLime, .mapFocus, .map3D:
            return "ion-whisper"
        case .plasma, .neon, .violetStorm, .warp, .cyberStorm:
            return "sport-ev"
        case .redline, .solarFlare, .plaidBoost, .desertDune:
            return "boost-launch"
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
    var wallpaper: EtubuWallpaperStyle = EtubuWallpaperStyle.stored
    /// Sheets pass `false` so settings List is not invalidated by 10 Hz telemetry.
    var live: Bool = true

    /// 0…1 — Model S Plaid launch heat (power + speed toward 100).
    private var plaidIntensity: CGFloat {
        guard live, theme == .plaidBoost else { return 0 }
        let t = EtubuVehicleTelemetry.shared
        let kmh = CGFloat(max(0, t.kmh))
        let power = CGFloat(max(0, t.powerKw ?? 0))
        let speedHeat = min(1, kmh / 100)
        let powerHeat = min(1, power / 220)
        // Parked: stay dark. Moving / torque: yellow→red wash.
        if kmh < 3, power < 20 { return 0 }
        return min(1, max(speedHeat * 0.55, powerHeat * 0.9, speedHeat * powerHeat * 1.15))
    }

    var body: some View {
        ZStack {
            if theme == .stealthOled {
                Color.black
            } else {
                LinearGradient(
                    colors: theme.canvasGradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                if theme == .plaidBoost {
                    plaidBoostWash
                } else {
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

                EtubuWallpaperOverlay(theme: theme, style: wallpaper, landscape: landscape)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.18), value: plaidIntensity)
        .animation(.easeInOut(duration: 0.25), value: wallpaper)
    }

    /// Tesla Model S Plaid 0–100: full-bleed heat that climbs yellow → orange → red.
    private var plaidBoostWash: some View {
        let i = plaidIntensity
        return ZStack {
            RadialGradient(
                colors: [
                    Color(red: 1.0, green: 0.55, blue: 0.08).opacity(0.12 + Double(i) * 0.28),
                    .clear,
                ],
                center: .center,
                startRadius: 40,
                endRadius: landscape ? 580 : 480
            )

            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.92, blue: 0.22).opacity(0.08 + Double(i) * 0.55),
                    Color(red: 1.0, green: 0.45, blue: 0.05).opacity(0.06 + Double(i) * 0.48),
                    Color(red: 0.9, green: 0.05, blue: 0.05).opacity(0.04 + Double(i) * 0.62),
                    Color.black.opacity(0.2),
                ],
                startPoint: landscape ? .leading : .bottom,
                endPoint: landscape ? .trailing : .top
            )
            .blendMode(.plusLighter)
            .opacity(0.35 + Double(i) * 0.65)

            RadialGradient(
                colors: [
                    Color(red: 1.0, green: 0.95, blue: 0.35).opacity(Double(i) * 0.45),
                    Color(red: 1.0, green: 0.2, blue: 0.05).opacity(Double(i) * 0.35),
                    .clear,
                ],
                center: .center,
                startRadius: 10,
                endRadius: landscape ? 320 : 280
            )
            .blendMode(.screen)
            .opacity(Double(i))
        }
    }
}

/// ETUBU speed unit (km/h vs mph) with automatic regional detection.
enum EtubuSpeedUnit: String, CaseIterable, Identifiable {
    case auto
    case kmh
    case mph

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return EtubuClusterL10n.t("unitAuto")
        case .kmh: return "km/h"
        case .mph: return "mph"
        }
    }

    /// Conversion factor from km/h
    static let kmhToMphMultiplier: Double = 0.621371192

    static var stored: EtubuSpeedUnit {
        get {
            let raw = UserDefaults.standard.string(forKey: "etubu.speed.unit") ?? "auto"
            return EtubuSpeedUnit(rawValue: raw) ?? .auto
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "etubu.speed.unit")
            NotificationCenter.default.post(name: .etubuSpeedUnitDidChange, object: nil)
        }
    }

    /// Whether MPH is currently active based on selection or region.
    var isMph: Bool {
        switch self {
        case .mph: return true
        case .kmh: return false
        case .auto:
            let regionCode = Locale.current.region?.identifier
                ?? Locale.current.regionCode
                ?? "TR"
            let mphRegions: Set<String> = ["US", "GB", "UK", "LR", "MM", "PR", "VI", "GU", "AS", "MP", "BS", "BZ"]
            return mphRegions.contains(regionCode.uppercased())
        }
    }

    var label: String { isMph ? "mph" : "km/h" }

    func convert(kmh: Double) -> Double {
        isMph ? kmh * Self.kmhToMphMultiplier : kmh
    }

    func format(kmh: Double) -> Int {
        Int(convert(kmh: kmh).rounded())
    }
}

extension Notification.Name {
    static let etubuSpeedUnitDidChange = Notification.Name("etubuSpeedUnitDidChange")
}
