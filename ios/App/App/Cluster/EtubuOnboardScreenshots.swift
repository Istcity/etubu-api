import SwiftUI

/// Tanıtım ekran görüntüleri — yalnızca resim + altta açıklama (işaretleme yok).
enum EtubuOnboardShot: Int, CaseIterable, Identifiable {
    case portrait
    case landscape
    case pair

    var id: Int { rawValue }

    var assetName: String {
        switch self {
        case .portrait: return "OnboardShotPortrait"
        case .landscape: return "OnboardShotLandscape"
        case .pair: return "OnboardShotPair"
        }
    }

    var caption: String {
        switch self {
        case .portrait: return "Dikey kadran"
        case .landscape: return "Yatay sürüş"
        case .pair: return "Pair / VIN"
        }
    }

    var tip: String {
        switch self {
        case .portrait: return "Rota için harita ikonu · Ses profili altta"
        case .landscape: return "Varış: sadece il / ilçe yazın"
        case .pair: return "VIN yazın → Pair · klavye üstünde kalır"
        }
    }

    static func forPage(_ index: Int) -> EtubuOnboardShot {
        switch index {
        case 0: return .portrait
        case 1: return .pair
        case 2: return .landscape
        default: return .portrait
        }
    }
}

struct EtubuOnboardScreenshotStrip: View {
    var theme: ClusterTheme
    var highlight: EtubuOnboardShot?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(EtubuOnboardShot.allCases) { shot in
                    EtubuOnboardScreenshotCard(
                        shot: shot,
                        theme: theme,
                        emphasized: highlight == nil || highlight == shot,
                        width: shot == .landscape ? 168 : 118,
                        height: shot == .landscape ? 96 : 198
                    )
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
    }
}

struct EtubuOnboardScreenshotCard: View {
    var shot: EtubuOnboardShot
    var theme: ClusterTheme
    var emphasized: Bool = true
    var width: CGFloat = 200
    var height: CGFloat = 280

    var body: some View {
        VStack(spacing: 8) {
            Image(shot.assetName)
                .resizable()
                .scaledToFill()
                .frame(width: width, height: height)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(theme.accent.opacity(emphasized ? 0.55 : 0.22), lineWidth: emphasized ? 1.5 : 1)
                )
                .shadow(color: theme.accent.opacity(emphasized ? 0.28 : 0.08), radius: emphasized ? 10 : 4, y: 3)
                .opacity(emphasized ? 1 : 0.55)
                .scaleEffect(emphasized ? 1 : 0.97)

            Text(shot.caption)
                .font(EtubuClusterFonts.ui(12, weight: .bold))
                .foregroundStyle(emphasized ? .white : theme.mutedText)
            Text(shot.tip)
                .font(EtubuClusterFonts.ui(10, weight: .medium))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: width)
        }
    }
}
