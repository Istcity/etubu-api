import SwiftUI

/// Ayarlar / rota / uzaktan kumanda sheet’leri — ana pano ile aynı zemin ve kart dili.
struct EtubuSheetBackdrop: View {
    var theme: ClusterTheme
    var wallpaper: EtubuWallpaperStyle = EtubuWallpaperStyle.stored

    var body: some View {
        ZStack {
            theme.canvas
            ClusterThemeBackdrop(theme: theme, landscape: false, wallpaper: wallpaper, live: false)
                .opacity(0.72)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Ayar grubu — başlık yanında 16pt döngü (taşmaz).
enum EtubuSheetSectionMotion {
    case language, app, vehicle, route, trip, remote, look, sound, alerts, premium, about
}

struct EtubuSheetSectionTitle: View {
    let title: String
    var theme: ClusterTheme
    var motion: EtubuSheetSectionMotion? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let motion {
                EtubuSheetSectionGlyph(kind: motion, accent: theme.accent)
            }
            Text(title)
                .font(EtubuClusterFonts.ui(11, weight: .heavy))
                .tracking(0.7)
                .foregroundStyle(theme.mutedText)
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .allowsTightening(true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct EtubuSheetSectionGlyph: View {
    let kind: EtubuSheetSectionMotion
    var accent: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(accent)
            .frame(width: 16, height: 16)
            .accessibilityHidden(true)
    }

    private var symbol: String {
        switch kind {
        case .language: return "globe"
        case .app: return "square.stack.fill"
        case .vehicle: return "car.fill"
        case .route: return "point.topleft.down.to.point.bottomright.curvepath"
        case .trip: return "chart.xyaxis.line"
        case .remote: return "car.side.front.open"
        case .look: return "paintpalette.fill"
        case .sound: return "speaker.wave.2.fill"
        case .alerts: return "exclamationmark.triangle.fill"
        case .premium: return "star.fill"
        case .about: return "info.circle.fill"
        }
    }
}

struct EtubuSheetHint: View {
    let text: String
    var theme: ClusterTheme

    var body: some View {
        Text(text)
            .font(EtubuClusterFonts.ui(12, weight: .medium))
            .foregroundStyle(theme.mutedText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct EtubuSheetCard: ViewModifier {
    var theme: ClusterTheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                shape.fill(
                    LinearGradient(
                        colors: [theme.surface.opacity(0.95), Color.black.opacity(0.32)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            )
            .overlay(shape.strokeBorder(theme.stroke.opacity(0.85), lineWidth: 1.15))
            .clipShape(shape)
            .shadow(color: Color.black.opacity(0.28), radius: 4, y: 2)
    }
}

extension View {
    func etubuSheetCard(_ theme: ClusterTheme) -> some View {
        modifier(EtubuSheetCard(theme: theme))
    }

    /// List satır zemini — `List` üzerindeki `listRowBackground` iOS’ta satırlara inmez.
    func etubuSheetSection(_ theme: ClusterTheme) -> some View {
        self
            .listRowBackground(theme.surface.opacity(0.92))
            .listRowSeparatorTint(theme.stroke.opacity(0.32))
    }

    func etubuSheetList(_ theme: ClusterTheme) -> some View {
        self
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
            .listSectionSpacing(14)
            .transaction { $0.animation = nil }
            .tint(theme.accent)
            .foregroundStyle(theme.primaryText)
            .environment(\.font, EtubuClusterFonts.ui(16, weight: .medium))
            .preferredColorScheme(.dark)
            .toolbarBackground(theme.canvas.opacity(0.94), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .background { EtubuSheetBackdrop(theme: theme) }
    }
}
