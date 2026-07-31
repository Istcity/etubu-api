import SwiftUI

/// Cutout FX — soft fade; speed-linked; **Canvas tema efektleri** (özgün 1:1).
/// iOS 18 RealityKit isteğe bağlı alt katman — tema kimliğini ezmez.
struct EtubuNotchAuraView: View {
    let kmh: Int
    let theme: ClusterTheme
    let cutout: EtubuCameraCutout.Geometry

    @State private var springKmh: CGFloat = 0

    private var fx: EtubuCutoutFX { .forTheme(theme) }

    private var drive: CGFloat {
        min(1, max(0, springKmh) / 130)
    }

    /// Dururken de görünür taban; hızda güçlenir
    private var motion: CGFloat {
        0.42 + drive * 0.58
    }

    private var growPt: CGFloat {
        6 + drive * 16
    }

    private var landscapeBoost: CGFloat {
        cutout.landscapeEdge != nil ? 1.18 : 1.0
    }

    private var themePresence: CGFloat {
        switch theme {
        case .midnight, .tunnel, .tesla, .deepOcean: return 1.45
        case .aurora, .electricIce: return 1.28
        case .cyberLime, .plasma, .violetStorm, .warp: return 1.35
        default: return 1.25
        }
    }

    private var frameInterval: Double {
        kmh < 2 ? 1.0 / 12.0 : 1.0 / 24.0
    }

    var body: some View {
        ZStack {
            canvasAura
            // RealityKit: ek derinlik — Canvas üstte tema özgünlüğünü korur
            if #available(iOS 18.0, *), kmh >= 8 {
                EtubuVFXCameraAnchorView(
                    manager: EtubuVFXManager.shared,
                    kmh: kmh,
                    theme: theme,
                    cutout: cutout
                )
                .opacity(0.35 + Double(drive) * 0.35)
                .allowsHitTesting(false)
            }
        }
        .allowsHitTesting(false)
        .accessibilityLabel(fx.title)
        .id(theme.id)
        .onAppear { springKmh = CGFloat(max(0, kmh)) }
        .onChange(of: kmh) { _, newValue in
            withAnimation(.interpolatingSpring(stiffness: 120, damping: 22)) {
                springKmh = CGFloat(max(0, newValue))
            }
        }
        .onAppear {
            EtubuVFXManager.shared.sync(theme: theme, cutout: cutout, kmh: kmh)
        }
    }

    private var canvasAura: some View {
        TimelineView(.animation(minimumInterval: frameInterval, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let tMotion = t * Double(0.14 + Double(motion) * 1.8)
            let metalIntensity = (0.55 + motion * 1.05) * landscapeBoost * themePresence

            Canvas { ctx, size in
                let island = CGRect(
                    x: cutout.pill.minX - cutout.aura.minX,
                    y: cutout.pill.minY - cutout.aura.minY,
                    width: cutout.pill.width,
                    height: cutout.pill.height
                )
                let edgeSafe = max(12, min(size.width, size.height) * 0.10)
                let roomX = max(0, min(island.minX, size.width - island.maxX) - edgeSafe)
                let roomY = max(0, min(island.minY, size.height - island.maxY) - edgeSafe)
                let maxPad = min(growPt * landscapeBoost, roomX, roomY, min(size.width, size.height) * 0.14)
                let grown = island.insetBy(dx: -maxPad, dy: -maxPad)

                var soft = ctx
                soft.addFilter(.blur(radius: 2.2 + motion * 1.4))
                soft.blendMode = .plusLighter
                fx.draw(
                    ctx: soft,
                    island: grown,
                    t: tMotion,
                    intensity: metalIntensity,
                    accent: theme.accent,
                    hue: theme.hue,
                    sizeBoost: (0.85 + drive * 0.45) * landscapeBoost,
                    motion: motion,
                    transparentGround: true
                )
            }
            .frame(width: cutout.aura.width, height: cutout.aura.height)
            .etubuCutoutMetal(fx: fx, time: tMotion, intensity: metalIntensity)
            .mask {
                Capsule()
                    .fill(
                        RadialGradient(
                            colors: [.white, .white.opacity(0.92), .white.opacity(0.35), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: max(cutout.aura.width, cutout.aura.height) * 0.62
                        )
                    )
                    .padding(edgeFadePadding)
                    .blur(radius: 12)
            }
            .opacity(0.72 + Double(motion) * 0.28)
        }
    }

    private var edgeFadePadding: CGFloat {
        max(6, min(cutout.aura.width, cutout.aura.height) * 0.06)
    }
}
