import SwiftUI

/// Cutout FX — soft fade only; particles clamped inside aura so no knife-cut edges.
struct EtubuNotchAuraView: View {
    let kmh: Int
    let theme: ClusterTheme
    let cutout: EtubuCameraCutout.Geometry

    private static let maxGrowPt: CGFloat = 8

    @State private var springKmh: CGFloat = 0

    private var fx: EtubuCutoutFX { .forTheme(theme) }

    private var drive: CGFloat {
        min(1, max(0, springKmh) / 140)
    }

    private var motion: CGFloat {
        0.06 + drive * 0.85
    }

    private var growPt: CGFloat {
        drive * Self.maxGrowPt
    }

    private var landscapeBoost: CGFloat {
        cutout.landscapeEdge != nil ? 1.0 : 1.0
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 36, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let tMotion = t * Double(0.10 + Double(motion) * 1.8)

            Canvas { ctx, size in
                let island = CGRect(
                    x: cutout.pill.minX - cutout.aura.minX,
                    y: cutout.pill.minY - cutout.aura.minY,
                    width: cutout.pill.width,
                    height: cutout.pill.height
                )
                // Hard inset from Canvas rect — nothing draws near the frame edge
                let edgeSafe = max(20, min(size.width, size.height) * 0.18)
                let roomX = max(0, min(island.minX, size.width - island.maxX) - edgeSafe)
                let roomY = max(0, min(island.minY, size.height - island.maxY) - edgeSafe)
                let maxPad = min(growPt * landscapeBoost + 2, roomX, roomY, min(size.width, size.height) * 0.10)
                let grown = island.insetBy(dx: -maxPad, dy: -maxPad)

                var soft = ctx
                soft.addFilter(.blur(radius: 5.5 + motion * 3.2))
                soft.blendMode = .plusLighter
                fx.draw(
                    ctx: soft,
                    island: grown,
                    t: tMotion,
                    intensity: (0.22 + motion * 0.85) * landscapeBoost,
                    accent: theme.accent,
                    hue: theme.hue,
                    sizeBoost: 0.55 * landscapeBoost,
                    motion: motion,
                    transparentGround: true
                )
            }
            .frame(width: cutout.aura.width, height: cutout.aura.height)
            // Soft capsule vignette — fully transparent before hard bounds
            .mask {
                Capsule()
                    .fill(.white)
                    .padding(edgeFadePadding)
                    .blur(radius: 14)
            }
            .opacity(0.95)
        }
        .compositingGroup()
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
        .accessibilityLabel(fx.title)
        .id(theme.id)
        .onAppear { springKmh = CGFloat(max(0, kmh)) }
        .onChange(of: kmh) { _, newValue in
            withAnimation(.interpolatingSpring(stiffness: 140, damping: 20)) {
                springKmh = CGFloat(max(0, newValue))
            }
        }
    }

    private var edgeFadePadding: CGFloat {
        max(12, min(cutout.aura.width, cutout.aura.height) * 0.12)
    }
}
