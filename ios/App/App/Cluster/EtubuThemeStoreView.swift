import SwiftUI

/// Extra atmosphere layered on `ClusterThemeBackdrop` (tema mağazası).
enum EtubuWallpaperStyle: String, CaseIterable, Identifiable {
    case atmospheric
    case mesh
    case grid
    case stars
    case minimal

    var id: String { rawValue }

    var title: String { EtubuClusterL10n.t("wallpaper.\(rawValue)") }

    var symbol: String {
        switch self {
        case .atmospheric: return "paintpalette.fill"
        case .mesh: return "circle.hexagongrid.fill"
        case .grid: return "grid"
        case .stars: return "sparkles"
        case .minimal: return "circle.lefthalf.filled"
        }
    }

    private static let storageKey = "etubu.cluster.wallpaper"

    static var stored: EtubuWallpaperStyle {
        get {
            if let raw = UserDefaults.standard.string(forKey: storageKey),
               let s = EtubuWallpaperStyle(rawValue: raw) {
                return s
            }
            return .atmospheric
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: storageKey) }
    }
}

/// Visual theme + wallpaper picker for Settings.
struct EtubuThemeStoreView: View {
    @Binding var theme: ClusterTheme
    @Binding var wallpaper: EtubuWallpaperStyle

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(EtubuClusterL10n.t("themeStoreThemes"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(ClusterTheme.allCases) { t in
                    themeTile(t)
                }
            }

            Text(EtubuClusterL10n.t("themeStoreWallpaper"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(EtubuWallpaperStyle.allCases) { style in
                        wallpaperChip(style)
                    }
                }
            }

            Text(EtubuClusterL10n.t("themeStoreHint"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func themeTile(_ t: ClusterTheme) -> some View {
        let selected = theme == t
        return Button {
            theme = t
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: t.canvasGradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Circle()
                        .fill(t.accent.opacity(0.85))
                        .frame(width: 18, height: 18)
                        .offset(x: 22, y: -10)
                        .blur(radius: 0.5)
                    Text(String(format: "%d", 88))
                        .font(.system(size: 22, weight: .bold, design: t.gaugeDesign))
                        .foregroundStyle(.white.opacity(0.92))
                }
                .frame(height: 64)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(selected ? t.accent : Color.primary.opacity(0.12), lineWidth: selected ? 2 : 1)
                )

                Text(t.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(EtubuCutoutFX.forTheme(t).title)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func wallpaperChip(_ style: EtubuWallpaperStyle) -> some View {
        let selected = wallpaper == style
        return Button {
            wallpaper = style
            EtubuWallpaperStyle.stored = style
        } label: {
            HStack(spacing: 6) {
                Image(systemName: style.symbol)
                    .font(.system(size: 12, weight: .semibold))
                Text(style.title)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(selected ? theme.accent.opacity(0.22) : Color.primary.opacity(0.06))
            )
            .overlay(
                Capsule()
                    .strokeBorder(selected ? theme.accent : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Pattern overlays drawn above the theme gradient.
struct EtubuWallpaperOverlay: View {
    let theme: ClusterTheme
    let style: EtubuWallpaperStyle
    var landscape: Bool = false

    var body: some View {
        switch style {
        case .atmospheric:
            EmptyView()
        case .minimal:
            Color.black.opacity(0.28)
        case .mesh:
            mesh
        case .grid:
            grid
        case .stars:
            stars
        }
    }

    private var mesh: some View {
        Canvas { ctx, size in
            let step: CGFloat = landscape ? 56 : 44
            var y: CGFloat = 0
            var row = 0
            while y < size.height + step {
                var x: CGFloat = row.isMultiple(of: 2) ? 0 : step * 0.5
                while x < size.width + step {
                    let r = CGRect(x: x - 14, y: y - 14, width: 28, height: 28)
                    ctx.stroke(
                        Path(ellipseIn: r),
                        with: .color(theme.accent.opacity(0.14)),
                        lineWidth: 1
                    )
                    x += step
                }
                y += step * 0.75
                row += 1
            }
        }
        .blendMode(.plusLighter)
        .opacity(0.85)
    }

    private var grid: some View {
        Canvas { ctx, size in
            let step: CGFloat = landscape ? 36 : 28
            var x: CGFloat = 0
            while x <= size.width {
                var p = Path()
                p.move(to: CGPoint(x: x, y: 0))
                p.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(p, with: .color(theme.accent.opacity(0.10)), lineWidth: 0.8)
                x += step
            }
            var y: CGFloat = 0
            while y <= size.height {
                var p = Path()
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(p, with: .color(theme.accent.opacity(0.08)), lineWidth: 0.8)
                y += step
            }
        }
        .blendMode(.plusLighter)
    }

    private var stars: some View {
        Canvas { ctx, size in
            var rng = SeededRNG(seed: UInt64(theme.hue.bitPattern))
            for _ in 0..<70 {
                let x = CGFloat(rng.next() % UInt64(max(1, Int(size.width))))
                let y = CGFloat(rng.next() % UInt64(max(1, Int(size.height))))
                let r = CGFloat(0.6 + Double(rng.next() % 18) / 10.0)
                let rect = CGRect(x: x, y: y, width: r, height: r)
                ctx.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(0.18 + Double(rng.next() % 40) / 100.0)))
            }
            for _ in 0..<12 {
                let x = CGFloat(rng.next() % UInt64(max(1, Int(size.width))))
                let y = CGFloat(rng.next() % UInt64(max(1, Int(size.height))))
                let glow = CGRect(x: x - 3, y: y - 3, width: 6, height: 6)
                ctx.fill(Path(ellipseIn: glow), with: .color(theme.accent.opacity(0.35)))
            }
        }
        .blendMode(.screen)
        .opacity(0.9)
    }
}

/// Tiny deterministic RNG for stable star fields per theme.
private struct SeededRNG {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
