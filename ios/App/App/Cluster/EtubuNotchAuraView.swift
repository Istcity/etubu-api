import SwiftUI

/// Cutout FX — rim locked to hardware pill mid; soft glow without edge-clipped blur bias.
struct EtubuNotchAuraView: View {
    let kmh: Int
    let theme: ClusterTheme
    let cutout: EtubuCameraCutout.Geometry

    @State private var springKmh: CGFloat = 0

    private var fx: EtubuCutoutFX { .forTheme(theme) }
    private var density: CGFloat { EtubuRuntimeProfile.fxDensity }

    private var drive: CGFloat {
        min(1, max(0, springKmh) / 130)
    }

    private var idle: Bool { springKmh < 2.5 }

    private var motion: CGFloat {
        if idle { return 0.05 * density }
        return (0.20 + drive * 0.45) * (0.55 + density * 0.45)
    }

    private var growPt: CGFloat {
        idle ? 1.5 : (3 + drive * 8) * density
    }

    private var frameInterval: Double {
        EtubuRuntimeProfile.fxFrameInterval(idle: idle)
    }

    /// Pill rect in aura-local coordinates (aura is always centered on pill).
    private var islandLocal: CGRect {
        CGRect(
            x: cutout.pill.minX - cutout.aura.minX,
            y: cutout.pill.minY - cutout.aura.minY,
            width: cutout.pill.width,
            height: cutout.pill.height
        )
    }

    var body: some View {
        ZStack {
            softPillHalo
            canvasAura
        }
        .frame(width: cutout.aura.width, height: cutout.aura.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .id(theme.id)
        .onAppear { springKmh = CGFloat(max(0, kmh)) }
        .onChange(of: kmh) { _, newValue in
            withAnimation(.interpolatingSpring(stiffness: 120, damping: 22)) {
                springKmh = CGFloat(max(0, newValue))
            }
        }
    }

    /// Soft rim — Canvas gradients (no UIView blur → no edge asymmetry).
    private var softPillHalo: some View {
        let island = islandLocal
        let pulse = idle ? 0.0 : (0.06 + Double(drive) * 0.12)
        return Canvas { ctx, _ in
            let core = Capsule().path(in: island)
            let soft = Capsule().path(in: island.insetBy(dx: -4, dy: -4))
            let outer = Capsule().path(in: island.insetBy(dx: -9, dy: -9))
            ctx.fill(outer, with: .color(theme.accent.opacity(0.07 + pulse * 0.18)))
            ctx.fill(soft, with: .color(theme.accent.opacity(0.12 + pulse * 0.22)))
            ctx.stroke(
                core,
                with: .color(theme.accent.opacity(0.38 + pulse * 0.35)),
                lineWidth: 1.35
            )
            ctx.stroke(
                Capsule().path(in: island.insetBy(dx: 0.5, dy: 0.5)),
                with: .color(Color.white.opacity(0.16 + pulse * 0.18)),
                lineWidth: 0.7
            )
        }
        .opacity(idle ? 0.78 : 0.95)
    }

    private var canvasAura: some View {
        TimelineView(.animation(minimumInterval: frameInterval, paused: idle)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let tMotion = t * Double(0.10 + Double(motion) * 1.15)
            let island = islandLocal

            Canvas { ctx, size in
                guard !idle else { return }
                let edgeSafe = max(10, min(size.width, size.height) * 0.10)
                let roomX = max(0, min(island.minX, size.width - island.maxX) - edgeSafe * 0.25)
                let roomY = max(0, min(island.minY, size.height - island.maxY) - edgeSafe * 0.25)
                let maxPad = min(growPt, roomX, roomY, min(size.width, size.height) * 0.07)
                let field = island.insetBy(dx: -maxPad, dy: -maxPad)

                var soft = ctx
                soft.blendMode = .plusLighter
                fx.draw(
                    ctx: soft,
                    island: field,
                    t: tMotion,
                    intensity: motion * 0.65 * density,
                    accent: theme.accent,
                    hue: theme.hue,
                    sizeBoost: (0.48 + drive * 0.26) * density,
                    motion: motion,
                    transparentGround: true
                )
            }
            .opacity(0.5 + Double(motion) * 0.28)
            .mask {
                Capsule()
                    .fill(
                        RadialGradient(
                            colors: [.white, .white.opacity(0.55), .clear],
                            center: .center,
                            startRadius: 2,
                            endRadius: max(cutout.pill.width, cutout.pill.height) * 1.15
                        )
                    )
                    .frame(width: cutout.pill.width * 2.1, height: cutout.pill.height * 2.1)
                    .position(x: islandLocal.midX, y: islandLocal.midY)
            }
        }
    }
}
