import SwiftUI

/// Cutout FX locked to the hardware pill. Glow hugs the rim so it reads as the
/// island itself — not an effect floating out from underneath.
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

    private var idle: Bool { springKmh < 3.5 }

    private var motion: CGFloat {
        if idle { return 0.04 * density }
        return (0.18 + drive * 0.40) * (0.55 + density * 0.45)
    }

    private var growPt: CGFloat {
        idle ? 1.0 : (2.5 + drive * 6) * density
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
            // Hardware seat — opaque core so nothing “bleeds” from under the cutout.
            Capsule()
                .fill(Color.black)
                .frame(width: cutout.pill.width, height: cutout.pill.height)
                .position(x: islandLocal.midX, y: islandLocal.midY)

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

    /// Tight rim only — no large soft blob that looks offset from the island.
    private var softPillHalo: some View {
        let island = islandLocal
        let pulse = idle ? 0.0 : (0.05 + Double(drive) * 0.10)
        // Portrait: keep outward rim short on the content side of the pill.
        let rimOut: CGFloat = {
            switch cutout.anchor {
            case .top, .bottom: return 4.0
            case .leading, .trailing: return 5.5
            }
        }()
        return Canvas { ctx, _ in
            let core = Capsule().path(in: island)
            let soft = Capsule().path(in: island.insetBy(dx: -2.0, dy: -2.0))
            let outer = Capsule().path(in: island.insetBy(dx: -rimOut, dy: -rimOut))
            ctx.fill(outer, with: .color(theme.accent.opacity(0.06 + pulse * 0.14)))
            ctx.fill(soft, with: .color(theme.accent.opacity(0.10 + pulse * 0.18)))
            ctx.stroke(
                core,
                with: .color(theme.accent.opacity(0.42 + pulse * 0.32)),
                lineWidth: 1.2
            )
            ctx.stroke(
                Capsule().path(in: island.insetBy(dx: 0.6, dy: 0.6)),
                with: .color(Color.white.opacity(0.14 + pulse * 0.14)),
                lineWidth: 0.65
            )
        }
        .opacity(idle ? 0.82 : 0.96)
        // Doughnut: keep glow on the rim, hollow over the black hardware pill.
        .mask {
            ZStack {
                Capsule()
                    .fill(Color.white)
                    .frame(
                        width: cutout.pill.width + rimOut * 2 + 2,
                        height: cutout.pill.height + rimOut * 2 + 2
                    )
                Capsule()
                    .fill(Color.black)
                    .frame(
                        width: max(4, cutout.pill.width - 1),
                        height: max(4, cutout.pill.height - 1)
                    )
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
            .frame(width: cutout.aura.width, height: cutout.aura.height)
            .position(x: islandLocal.midX, y: islandLocal.midY)
        }
    }

    private var canvasAura: some View {
        TimelineView(.animation(minimumInterval: frameInterval, paused: idle)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let tMotion = t * Double(0.10 + Double(motion) * 1.15)
            let island = islandLocal

            Canvas { ctx, size in
                guard !idle else { return }
                let roomX = max(0, min(island.minX, size.width - island.maxX) - 4)
                let roomY = max(0, min(island.minY, size.height - island.maxY) - 4)
                // Portrait: cap particle reach toward content so FX stays on the rim.
                let padCap: CGFloat = {
                    switch cutout.anchor {
                    case .top, .bottom: return 7
                    case .leading, .trailing: return 10
                    }
                }()
                let maxPad = min(growPt, roomX, roomY, padCap)
                let field = island.insetBy(dx: -maxPad, dy: -maxPad)

                var soft = ctx
                soft.blendMode = .plusLighter
                fx.draw(
                    ctx: soft,
                    island: field,
                    t: tMotion,
                    intensity: motion * 0.55 * density,
                    accent: theme.accent,
                    hue: theme.hue,
                    sizeBoost: (0.42 + drive * 0.22) * density,
                    motion: motion,
                    transparentGround: true
                )
            }
            .opacity(0.45 + Double(motion) * 0.28)
            .mask {
                // Rim-only particle field — hollow center = cutout body.
                ZStack {
                    Capsule()
                        .fill(
                            RadialGradient(
                                colors: [.white.opacity(0.95), .white.opacity(0.35), .clear],
                                center: .center,
                                startRadius: 1,
                                endRadius: max(cutout.pill.width, cutout.pill.height) * 0.95
                            )
                        )
                        .frame(
                            width: cutout.pill.width + growPt * 2.2,
                            height: cutout.pill.height + growPt * 2.2
                        )
                    Capsule()
                        .fill(Color.black)
                        .frame(
                            width: max(6, cutout.pill.width * 0.92),
                            height: max(6, cutout.pill.height * 0.92)
                        )
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
                .frame(width: cutout.aura.width, height: cutout.aura.height)
                .position(x: islandLocal.midX, y: islandLocal.midY)
            }
        }
    }
}
