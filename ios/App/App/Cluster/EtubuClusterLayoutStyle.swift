import SwiftUI

/// Dashboard layout presentation modes:
/// 1. `dualDial`: Symmetrical dual round dials (Speedometer on left, unified center alerts/corridor & tires in middle, symmetrical multi-gauge on right).
/// 2. `classicCards`: Classic HUD (Speedometer on left, twin alert cards in center, swipeable information cards on right).
enum EtubuClusterLayoutStyle: String, CaseIterable, Identifiable {
    case dualDial = "dualDial"
    case classicCards = "classicCards"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dualDial: return EtubuClusterL10n.t("layoutStyle.dualDial")
        case .classicCards: return EtubuClusterL10n.t("layoutStyle.classicCards")
        }
    }

    var description: String {
        switch self {
        case .dualDial: return EtubuClusterL10n.t("layoutStyle.dualDialDesc")
        case .classicCards: return EtubuClusterL10n.t("layoutStyle.classicCardsDesc")
        }
    }

    var icon: String {
        switch self {
        case .dualDial: return "gauge.with.dots.needle.bottom.100percent"
        case .classicCards: return "rectangle.split.3x1.fill"
        }
    }

    private static let storageKey = "etubu.cluster.layoutStyle"

    static var stored: EtubuClusterLayoutStyle {
        get {
            if let raw = UserDefaults.standard.string(forKey: storageKey),
               let style = EtubuClusterLayoutStyle(rawValue: raw) {
                return style
            }
            return .dualDial
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey)
        }
    }
}
