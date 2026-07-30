import SwiftUI
import UIKit

/// Theme-aware cluster fonts — gauge + UI family change per theme.
enum EtubuClusterFonts {
    /// Extra scale for landscape.
    static var layoutBoost: CGFloat = 0.9

    /// Active theme fonts — updated by `setTheme()`.
    private(set) static var gaugeFamily = "Orbitron"
    private(set) static var uiFamily = "DM Sans"

    static func setTheme(_ theme: ClusterTheme) {
        gaugeFamily = theme.gaugeFont
        uiFamily = theme.uiFont
    }

    static var displayScale: CGFloat {
        let b = UIScreen.main.bounds
        let longSide = max(b.width, b.height)
        if longSide >= 920 { return 1.10 }
        if longSide >= 880 { return 1.06 }
        if longSide >= 840 { return 1.02 }
        if longSide >= 780 { return 0.96 }
        return 0.90
    }

    private static var scale: CGFloat { displayScale * layoutBoost }

    static func gauge(_ size: CGFloat, weight: UIFont.Weight = .bold) -> Font {
        Font(resolved(family: gaugeFamily, size: size * scale, weight: weight, fallbackDesign: .rounded))
    }

    static func ui(_ size: CGFloat, weight: UIFont.Weight = .regular) -> Font {
        Font(resolved(family: uiFamily, size: size * scale, weight: weight, fallbackDesign: .default))
    }

    static func ui(_ textStyle: Font.TextStyle, weight: UIFont.Weight = .regular) -> Font {
        let size = UIFont.preferredFont(forTextStyle: textStyle.uiKit).pointSize
        return ui(size, weight: weight)
    }

    private static func resolved(
        family: String,
        size: CGFloat,
        weight: UIFont.Weight,
        fallbackDesign: UIFontDescriptor.SystemDesign
    ) -> UIFont {
        let candidates: [String] = {
            switch weight {
            case .black: return ["\(family)-Black", "\(family)-ExtraBold", "\(family)-Bold", family]
            case .heavy, .bold: return ["\(family)-Bold", "\(family)-SemiBold", "\(family)-Medium", family]
            case .semibold: return ["\(family)-SemiBold", "\(family)-Medium", "\(family)-Bold", family]
            case .medium: return ["\(family)-Medium", "\(family)-Regular", family]
            case .light: return ["\(family)-Light", "\(family)-Regular", family]
            default: return ["\(family)-Regular", family]
            }
        }()

        let spaced = family.replacingOccurrences(of: " ", with: "")
        let expanded = candidates.flatMap { name -> [String] in
            if name == family { return [family, spaced] }
            let dashed = name.replacingOccurrences(of: " ", with: "")
            return [name, dashed, name.replacingOccurrences(of: family, with: spaced)]
        }

        for name in expanded {
            if let font = UIFont(name: name, size: size) {
                return font
            }
        }

        if let base = UIFont(name: family, size: size) ?? UIFont(name: spaced, size: size) {
            let traits: [UIFontDescriptor.TraitKey: Any] = [.weight: weight]
            let desc = base.fontDescriptor.addingAttributes([.traits: traits])
            return UIFont(descriptor: desc, size: size)
        }

        let sys = UIFont.systemFont(ofSize: size, weight: weight)
        if let designed = sys.fontDescriptor.withDesign(fallbackDesign) {
            return UIFont(descriptor: designed, size: size)
        }
        return sys
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
