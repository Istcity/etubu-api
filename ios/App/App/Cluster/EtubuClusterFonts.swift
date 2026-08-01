import SwiftUI
import UIKit

/// Theme-aware cluster fonts — gauge + UI family, design, weight and scale change per theme.
enum EtubuClusterFonts {
    /// Extra scale for landscape (legacy; prefer `setContentScale` from layout metrics).
    static var layoutBoost: CGFloat = 0.9

    /// Full content scale from `EtubuClusterLayoutMetrics` (device + orientation).
    private(set) static var contentScale: CGFloat = 1.0
    private static var useContentScale = false

    /// Active theme fonts — updated by `setTheme()`.
    private(set) static var gaugeFamily = "Orbitron-Bold"
    private(set) static var uiFamily = "DMSans-Regular"
    private(set) static var gaugeDesign: Font.Design = .rounded
    private(set) static var uiDesign: Font.Design = .default
    private(set) static var gaugeWeight: Font.Weight = .bold
    private(set) static var gaugeScale: CGFloat = 1.0
    private(set) static var gaugeTracking: CGFloat = 1.0

    static func setTheme(_ theme: ClusterTheme) {
        gaugeFamily = theme.gaugeFont
        uiFamily = theme.uiFont
        gaugeDesign = theme.gaugeDesign
        uiDesign = theme.uiDesign
        gaugeWeight = theme.gaugeWeight
        gaugeScale = theme.gaugeScale
        gaugeTracking = theme.gaugeTracking
    }

    /// Apply canvas-derived scale (SE…Pro Max). Call from onAppear / onChange — not during body layout math.
    static func setContentScale(_ scale: CGFloat) {
        let next = min(1.28, max(0.72, scale))
        guard abs(contentScale - next) > 0.001 || !useContentScale else { return }
        contentScale = next
        useContentScale = true
        // Keep legacy boost in sync for any leftover readers.
        layoutBoost = next
    }

    static var displayScale: CGFloat {
        if useContentScale { return contentScale }
        // Fallback before first metrics pass — scene bounds, not UIScreen when possible.
        let longSide = sceneLongSide()
        if longSide >= 920 { return 1.10 }
        if longSide >= 880 { return 1.06 }
        if longSide >= 840 { return 1.02 }
        if longSide >= 780 { return 0.96 }
        return 0.90
    }

    private static var scale: CGFloat {
        if useContentScale { return contentScale }
        return displayScale * layoutBoost
    }

    private static func sceneLongSide() -> CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first {
            let b = scene.coordinateSpace.bounds
            if b.width > 40, b.height > 40 { return max(b.width, b.height) }
            let s = scene.screen.bounds
            return max(s.width, s.height)
        }
        let b = UIScreen.main.bounds
        return max(b.width, b.height)
    }

    static func gauge(_ size: CGFloat, weight: UIFont.Weight? = nil) -> Font {
        let w = weight ?? uiKitWeight(gaugeWeight)
        let px = size * scale * gaugeScale
        if let font = UIFont(name: gaugeFamily, size: px)
            ?? resolvedFamily(gaugeFamily, size: px, weight: w) {
            return Font(font)
        }
        return .system(size: px, weight: gaugeWeight, design: gaugeDesign)
    }

    static func ui(_ size: CGFloat, weight: UIFont.Weight = .regular) -> Font {
        let px = size * scale
        if let font = UIFont(name: uiFamily, size: px)
            ?? resolvedFamily(uiFamily, size: px, weight: weight) {
            return Font(font)
        }
        return .system(size: px, weight: swiftWeight(weight), design: uiDesign)
    }

    static func ui(_ textStyle: Font.TextStyle, weight: UIFont.Weight = .regular) -> Font {
        let size = UIFont.preferredFont(forTextStyle: textStyle.uiKit).pointSize
        return ui(size, weight: weight)
    }

    private static func resolvedFamily(_ family: String, size: CGFloat, weight: UIFont.Weight) -> UIFont? {
        let base = family
            .replacingOccurrences(of: "-Bold", with: "")
            .replacingOccurrences(of: "-Regular", with: "")
            .replacingOccurrences(of: "-Medium", with: "")
            .replacingOccurrences(of: "-DemiBold", with: "")
            .replacingOccurrences(of: "-Black", with: "")
            .replacingOccurrences(of: "-Heavy", with: "")
            .replacingOccurrences(of: "PSMT", with: "")
            .replacingOccurrences(of: "PS-BoldMT", with: "")
        let spaced = base.replacingOccurrences(of: " ", with: "")
        let candidates = [
            family,
            base,
            spaced,
            "\(base)-Bold",
            "\(base)-Regular",
            "\(spaced)-Bold",
            "\(spaced)Bold",
            "\(spaced)-Regular",
        ]
        for name in candidates {
            if let font = UIFont(name: name, size: size) { return font }
        }
        // Last resort: match by family name prefix in installed fonts
        let all = UIFont.familyNames.flatMap { UIFont.fontNames(forFamilyName: $0) }
        let needle = spaced.lowercased()
        if let hit = all.first(where: { $0.replacingOccurrences(of: " ", with: "").lowercased().contains(needle.prefix(6)) }) {
            return UIFont(name: hit, size: size)
        }
        return nil
    }

    private static func uiKitWeight(_ w: Font.Weight) -> UIFont.Weight {
        switch w {
        case .black: return .black
        case .heavy: return .heavy
        case .bold: return .bold
        case .semibold: return .semibold
        case .medium: return .medium
        case .light: return .light
        default: return .regular
        }
    }

    private static func swiftWeight(_ w: UIFont.Weight) -> Font.Weight {
        switch w {
        case .black: return .black
        case .heavy: return .heavy
        case .bold: return .bold
        case .semibold: return .semibold
        case .medium: return .medium
        case .light: return .light
        default: return .regular
        }
    }
}

private extension Font.TextStyle {
    var uiKit: UIFont.TextStyle {
        switch self {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .body: return .body
        case .callout: return .callout
        case .subheadline: return .subheadline
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        @unknown default: return .body
        }
    }
}
