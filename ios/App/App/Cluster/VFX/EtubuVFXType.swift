import Foundation
import SwiftUI

/// Photorealistic cutout VFX catalog — camera hole / Dynamic Island perimeter effects.
enum EtubuVFXType: String, CaseIterable, Identifiable, Codable {
    case elektrik
    case ates
    case duman
    case patlama
    case dalga
    case su
    case ruzgar
    case hiz
    case havaFisek
    case yildizKaymasi
    case yanardag

    var id: String { rawValue }

    var title: String {
        EtubuClusterL10n.t("vfx.\(rawValue)")
    }

    /// Max birth radius buffer around the cutout rim (0.5 cm ≈ 14 pt @ ~460 ppi).
    static let rimBufferPoints: CGFloat = 14
    static let rimBufferMeters: Float = 0.005

    /// Theme → VFX (1 theme maps to one of the 11 photoreal modules).
    static func forTheme(_ theme: ClusterTheme) -> EtubuVFXType {
        switch theme {
        case .cyberLime, .violetStorm: return .elektrik
        case .redline: return .ates
        case .midnight, .tesla: return .duman
        case .neon: return .patlama
        case .deepOcean: return .dalga
        case .electricIce: return .su
        case .warp: return .ruzgar
        case .tunnel: return .hiz
        case .solarFlare: return .havaFisek
        case .aurora: return .yildizKaymasi
        case .plasma: return .yanardag
        }
    }

    /// Performance tier: particle budget multiplier (1 = Pro Max class).
    enum PerformanceTier: Float {
        case base = 0.45
        case standard = 0.7
        case pro = 1.0
        case proMax = 1.15
    }
}
