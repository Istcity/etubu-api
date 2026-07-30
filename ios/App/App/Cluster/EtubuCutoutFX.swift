import SwiftUI

/// Named cutout FX library — **one unique effect per ClusterTheme** (12 = 12).
enum EtubuCutoutFX: String, CaseIterable, Identifiable {
    case elektrik      // cyberLime
    case ates          // redline
    case duman         // midnight
    case patlama       // neon
    case isikHuzmesi   // aurora
    case buzKristali   // electricIce
    case warpHalka     // warp
    case plazma        // plasma
    case solarCorona   // solarFlare
    case yildirimMor   // violetStorm
    case okyanusDalga  // deepOcean
    case tunelCizgi    // tunnel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .elektrik: return "Elektrik"
        case .ates: return "Ateş"
        case .duman: return "Duman"
        case .patlama: return "Patlama"
        case .isikHuzmesi: return "Işık Hüzmesi"
        case .buzKristali: return "Buz Kristali"
        case .warpHalka: return "Warp Halka"
        case .plazma: return "Plazma"
        case .solarCorona: return "Güneş Koronası"
        case .yildirimMor: return "Mor Yıldırım"
        case .okyanusDalga: return "Okyanus Dalga"
        case .tunelCizgi: return "Tünel Çizgi"
        }
    }

    /// Strict 1:1 with themes — never share FX across themes.
    static func forTheme(_ theme: ClusterTheme) -> EtubuCutoutFX {
        switch theme {
        case .cyberLime: return .elektrik
        case .redline: return .ates
        case .midnight: return .duman
        case .neon: return .patlama
        case .aurora: return .isikHuzmesi
        case .electricIce: return .buzKristali
        case .warp: return .warpHalka
        case .plasma: return .plazma
        case .solarFlare: return .solarCorona
        case .violetStorm: return .yildirimMor
        case .deepOcean: return .okyanusDalga
        case .tunnel: return .tunelCizgi
        }
    }

    func draw(
        ctx: GraphicsContext,
        island: CGRect,
        t: Double,
        intensity: CGFloat,
        accent: Color,
        hue: Double,
        sizeBoost: CGFloat = 1,
        motion: CGFloat = 1,
        transparentGround: Bool = false
    ) {
        let base = max(0.95, min(1.65, max(island.width, island.height) / 110))
        // Transparent notch FX: keep particles short so soft fade never meets a hard clip
        let scaleCap: CGFloat = transparentGround ? 0.85 : 1.65
        let scale = min(scaleCap, base * max(0.55, min(1.15, sizeBoost)))
        let gated = max(0.10, min(transparentGround ? 1.05 : 1.8, intensity * max(0.12, motion)))
        switch self {
        case .elektrik: Self.drawElectric(ctx: ctx, island: island, t: t, intensity: gated, scale: scale, clearGround: transparentGround)
        case .ates: Self.drawFire(ctx: ctx, island: island, t: t, intensity: gated, scale: scale, clearGround: transparentGround)
        case .duman: Self.drawSmoke(ctx: ctx, island: island, t: t, intensity: gated, scale: scale, clearGround: transparentGround)
        case .patlama: Self.drawExplosion(ctx: ctx, island: island, t: t, intensity: gated, scale: scale, clearGround: transparentGround)
        case .isikHuzmesi: Self.drawBeam(ctx: ctx, island: island, t: t, intensity: gated, scale: scale, accent: accent, clearGround: transparentGround)
        case .buzKristali: Self.drawFrost(ctx: ctx, island: island, t: t, intensity: gated, scale: scale, clearGround: transparentGround)
        case .warpHalka: Self.drawWarp(ctx: ctx, island: island, t: t, intensity: gated, scale: scale, accent: accent)
        case .plazma: Self.drawPlasma(ctx: ctx, island: island, t: t, intensity: gated, scale: scale, hue: hue)
        case .solarCorona: Self.drawSolarCorona(ctx: ctx, island: island, t: t, intensity: gated, scale: scale, clearGround: transparentGround)
        case .yildirimMor: Self.drawVioletStorm(ctx: ctx, island: island, t: t, intensity: gated, scale: scale, clearGround: transparentGround)
        case .okyanusDalga: Self.drawOceanWave(ctx: ctx, island: island, t: t, intensity: gated, scale: scale, accent: accent, clearGround: transparentGround)
        case .tunelCizgi: Self.drawTunnelLines(ctx: ctx, island: island, t: t, intensity: gated, scale: scale, accent: accent, clearGround: transparentGround)
        }
    }
}

// MARK: - Drawing (realistic particle / field FX)

private extension EtubuCutoutFX {

    /// Branched lightning bolts — bright white/cyan arcs from pill edges (reference Elektrik).
    static func drawElectric(ctx: GraphicsContext, island: CGRect, t: Double, intensity: CGFloat, scale: CGFloat, clearGround: Bool = false) {
        let c = CGPoint(x: island.midX, y: island.midY)
        if !clearGround {
            ctx.fill(Capsule().path(in: island.insetBy(dx: -6, dy: -6)), with: .color(Color.cyan.opacity(0.22 + 0.12 * abs(sin(t * 10)))))
            ctx.fill(Capsule().path(in: island.insetBy(dx: -2, dy: -2)), with: .color(Color.white.opacity(0.18 + 0.1 * abs(sin(t * 14)))))
        }

        let bolts = 10 + Int(intensity * 6)
        for i in 0..<bolts {
            let baseAng = Double(i) / Double(bolts) * .pi * 2 + t * (2.2 + Double(intensity) * 0.7)
            var path = Path()
            var p = EtubuCutoutGeom.pointOnCapsule(island.insetBy(dx: -1, dy: -1), u: frag(baseAng / (.pi * 2)))
            path.move(to: p)
            let segs = 7 + Int(intensity * 2)
            let reach = (40 + intensity * 52) * scale
            for s in 1...segs {
                let f = CGFloat(s) / CGFloat(segs)
                let ang = baseAng + sin(t * 28 + Double(i * 5 + s)) * 0.48
                if s == segs / 2 || s == segs * 2 / 3 {
                    var fork = Path()
                    fork.move(to: p)
                    let fang = ang + (i % 2 == 0 ? 0.65 : -0.65)
                    let fp = CGPoint(
                        x: p.x + cos(fang) * reach * 0.42,
                        y: p.y + sin(fang) * reach * 0.42
                    )
                    fork.addLine(to: fp)
                    strokeBolt(ctx: ctx, path: fork, scale: scale, hot: true)
                }
                let jx = CGFloat(sin(t * 52 + Double(i * 13 + s * 7))) * (6 + intensity * 5) * scale
                let jy = CGFloat(cos(t * 44 + Double(i * 11 + s))) * (6 + intensity * 5) * scale
                p = CGPoint(x: c.x + cos(ang) * reach * f + jx, y: c.y + sin(ang) * reach * f + jy)
                path.addLine(to: p)
            }
            strokeBolt(ctx: ctx, path: path, scale: scale, hot: i % 2 == 0)
        }

        for i in 0..<14 {
            let u = frag(t * 0.85 + Double(i) / 14)
            let p = EtubuCutoutGeom.pointOnCapsule(island.insetBy(dx: -8 * scale, dy: -8 * scale), u: u)
            let r = (2.0 + intensity * 0.9) * scale
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 2.4, y: p.y - r * 2.4, width: r * 4.8, height: r * 4.8)), with: .color(Color.cyan.opacity(0.4)))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(Color.white.opacity(0.98)))
        }
    }

    static func strokeBolt(ctx: GraphicsContext, path: Path, scale: CGFloat, hot: Bool) {
        ctx.stroke(path, with: .color(Color.cyan.opacity(0.32)), style: StrokeStyle(lineWidth: 7.5 * scale, lineCap: .round, lineJoin: .round))
        ctx.stroke(path, with: .color(Color(red: 0.55, green: 0.88, blue: 1).opacity(0.9)), style: StrokeStyle(lineWidth: 2.8 * scale, lineCap: .round, lineJoin: .round))
        ctx.stroke(path, with: .color(Color.white.opacity(hot ? 0.98 : 0.75)), style: StrokeStyle(lineWidth: (hot ? 1.35 : 0.9) * scale, lineCap: .round, lineJoin: .round))
    }

    /// Flame ring wrapping the pill + rising tongues + embers (reference Ateş).
    static func drawFire(ctx: GraphicsContext, island: CGRect, t: Double, intensity: CGFloat, scale: CGFloat, clearGround: Bool = false) {
        let ring = island.insetBy(dx: -4 * scale, dy: -5 * scale)
        if !clearGround {
            ctx.fill(Capsule().path(in: island.insetBy(dx: -10 * scale, dy: -10 * scale)), with: .color(Color.orange.opacity(0.28)))
            ctx.fill(Capsule().path(in: island.insetBy(dx: -4 * scale, dy: -4 * scale)), with: .color(Color.yellow.opacity(0.16)))
        }

        for i in 0..<28 {
            let u = frag(Double(i) / 24 + t * 0.12)
            let base = EtubuCutoutGeom.pointOnCapsule(ring, u: u)
            let outward = CGPoint(x: base.x - island.midX, y: base.y - island.midY)
            let len = max(1, hypot(outward.x, outward.y))
            let nx = outward.x / len
            let ny = outward.y / len
            // Prefer upward bias like reference flames
            let upBias: CGFloat = -0.35
            let rise = CGFloat((t * (22 + Double(i % 5) * 6) + Double(i) * 7).truncatingRemainder(dividingBy: 55))
            let flicker = CGFloat(sin(t * 18 + Double(i) * 1.9)) * 5 * scale
            let tip = CGPoint(
                x: base.x + nx * (22 + rise * 0.85) * scale + ny * flicker,
                y: base.y + (ny + upBias) * (22 + rise * 0.85) * scale - nx * flicker * 0.35
            )
            var flame = Path()
            let side = 6.5 * scale
            flame.move(to: CGPoint(x: base.x - ny * side, y: base.y + nx * side))
            flame.addQuadCurve(to: tip, control: CGPoint(x: base.x + nx * 10 * scale - ny * side * 0.25, y: base.y + ny * 10 * scale + nx * side * 0.25))
            flame.addQuadCurve(to: CGPoint(x: base.x + ny * side, y: base.y - nx * side), control: CGPoint(x: tip.x + ny * 2.5, y: tip.y - nx * 2.5))
            flame.closeSubpath()
            let life = max(0.15, 1 - rise / 58)
            let hue = 0.04 + Double(i % 4) * 0.018
            ctx.fill(flame, with: .color(Color(hue: hue, saturation: 1, brightness: 1).opacity(0.72 * life * Double(min(1.5, intensity)))))
            ctx.fill(
                Path(ellipseIn: CGRect(x: tip.x - 2.6 * scale, y: tip.y - 2.6 * scale, width: 5.2 * scale, height: 5.2 * scale)),
                with: .color(Color.yellow.opacity(0.85 * life))
            )
        }
        for i in 0..<22 {
            let ang = Double(i) / 22 * .pi * 2 + t * 1.5
            let dist = (20 + CGFloat((t * 32 + Double(i) * 11).truncatingRemainder(dividingBy: 55))) * scale
            let p = CGPoint(x: island.midX + cos(ang) * dist, y: island.midY + sin(ang) * dist * 0.88 - dist * 0.12)
            let life = max(0, 1 - (dist / scale - 20) / 55)
            let sz = (1.4 + intensity * 0.7) * scale * life
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - sz, y: p.y - sz, width: sz * 2, height: sz * 2)), with: .color(Color.orange.opacity(0.9 * life)))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - sz * 0.45, y: p.y - sz * 0.45, width: sz * 0.9, height: sz * 0.9)), with: .color(Color.yellow.opacity(0.7 * life)))
        }
        ctx.stroke(Capsule().path(in: island.insetBy(dx: -2, dy: -2)), with: .color(Color.orange.opacity(0.65 + 0.2 * sin(t * 5))), lineWidth: 2.8 * scale)
    }

    /// Dense dark billows expanding from the cutout (reference Duman).
    static func drawSmoke(ctx: GraphicsContext, island: CGRect, t: Double, intensity: CGFloat, scale: CGFloat, clearGround: Bool = false) {
        if !clearGround {
            ctx.fill(Capsule().path(in: island.insetBy(dx: -10 * scale, dy: -9 * scale)), with: .color(Color.black.opacity(0.35)))
        }
        for i in 0..<24 {
            let u = frag(Double(i) / 24 + t * 0.04)
            let base = EtubuCutoutGeom.pointOnCapsule(island.insetBy(dx: -2, dy: -2), u: u)
            let rise = CGFloat((t * (10 + Double(i % 5) * 2.8) + Double(i) * 15).truncatingRemainder(dividingBy: 110))
            let sway = sin(t * 1.05 + Double(i) * 0.75) * (14 + rise * 0.16) * scale
            let x = base.x + sway
            let y = base.y - rise * 0.55 * scale + cos(t * 0.85 + Double(i)) * 6 * scale
            let r = (14 + rise * 0.32 + intensity * 6) * scale
            let life = max(0, 1 - rise / 110)
            let gray = 0.06 + Double(i % 5) * 0.05
            let smokeOp = clearGround ? 0.22 : 0.55
            ctx.fill(
                Path(ellipseIn: CGRect(x: x - r, y: y - r * 0.85, width: r * 2.2, height: r * 1.7)),
                with: .color(Color(white: gray).opacity(smokeOp * life))
            )
            ctx.fill(
                Path(ellipseIn: CGRect(x: x - r * 0.5, y: y - r * 0.4, width: r, height: r * 0.75)),
                with: .color(Color.white.opacity(0.06 * life))
            )
        }
        if !clearGround {
            ctx.fill(Capsule().path(in: island.insetBy(dx: -6, dy: -5)), with: .color(Color.black.opacity(0.5)))
        }
    }

    /// Cinematic blast — white core, orange shell, flying sparks (reference Patlama).
    static func drawExplosion(ctx: GraphicsContext, island: CGRect, t: Double, intensity: CGFloat, scale: CGFloat, clearGround: Bool = false) {
        let pulse = (t * 0.72).truncatingRemainder(dividingBy: 1)
        let blast = 1 - pow(1 - min(1, max(0, pulse)), 2.2)
        let c = CGPoint(x: island.midX, y: island.midY)

        for k in 0..<5 {
            let expand = (12 + CGFloat(blast) * (58 + intensity * 38) + CGFloat(k) * 14) * scale
            let op = max(0, (0.7 - Double(k) * 0.12) * (1 - blast))
            ctx.stroke(
                Path(ellipseIn: CGRect(x: c.x - expand, y: c.y - expand * 0.78, width: expand * 2, height: expand * 1.56)),
                with: .color(Color.orange.opacity(op)),
                lineWidth: (3.6 - CGFloat(k) * 0.5) * scale
            )
        }

        let coreR = (12 + CGFloat(blast) * 26 * intensity) * scale
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - coreR * 2.4, y: c.y - coreR * 1.6, width: coreR * 4.8, height: coreR * 3.2)), with: .color(Color.orange.opacity(0.35 * (1 - blast))))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - coreR * 1.6, y: c.y - coreR * 1.1, width: coreR * 3.2, height: coreR * 2.2)), with: .color(Color.yellow.opacity(0.55 * (1 - blast))))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - coreR, y: c.y - coreR * 0.75, width: coreR * 2, height: coreR * 1.5)), with: .color(Color.white.opacity(0.95 * (1 - blast * 0.6))))

        let sparkN = 28 + Int(intensity * 12)
        for i in 0..<sparkN {
            let ang = Double(i) / Double(sparkN) * .pi * 2 + t * 0.3
            let dist = CGFloat(blast) * (48 + intensity * 55) * scale * (0.4 + CGFloat((i * 19) % 11) / 11)
            let p = CGPoint(x: c.x + cos(ang) * dist, y: c.y + sin(ang) * dist * 0.88)
            let life = max(0, 1 - blast)
            let sz = (1.6 + intensity) * scale
            var streak = Path()
            streak.move(to: CGPoint(x: p.x - cos(ang) * sz * 4, y: p.y - sin(ang) * sz * 4))
            streak.addLine(to: p)
            ctx.stroke(streak, with: .color(Color.orange.opacity(0.8 * life)), style: StrokeStyle(lineWidth: sz * 0.85, lineCap: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - sz, y: p.y - sz, width: sz * 2, height: sz * 2)), with: .color(Color.white.opacity(0.95 * life)))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - sz * 0.45, y: p.y - sz * 0.45, width: sz * 0.9, height: sz * 0.9)), with: .color(Color.yellow.opacity(0.8 * life)))
        }
        ctx.stroke(Capsule().path(in: island), with: .color(Color.white.opacity(0.5 + 0.45 * (1 - blast))), lineWidth: 1.8 * scale)
    }

    static func drawBeam(ctx: GraphicsContext, island: CGRect, t: Double, intensity: CGFloat, scale: CGFloat, accent: Color, clearGround: Bool = false) {
        let c = CGPoint(x: island.midX, y: island.midY)
        for i in 0..<10 {
            let ang = Double(i) / 10 * .pi * 2 + t * 0.28
            let len = (55 + intensity * 45 + CGFloat(sin(t * 2.8 + Double(i))) * 12) * scale
            let half = (2.5 + intensity * 2.2) * scale * (0.55 + 0.45 * abs(sin(t * 3 + Double(i))))
            let ax = cos(ang); let ay = sin(ang)
            let px = -ay; let py = ax
            var beam = Path()
            beam.move(to: CGPoint(x: c.x + px * half, y: c.y + py * half))
            beam.addLine(to: CGPoint(x: c.x + ax * len + px * half * 0.15, y: c.y + ay * len + py * half * 0.15))
            beam.addLine(to: CGPoint(x: c.x + ax * len - px * half * 0.15, y: c.y + ay * len - py * half * 0.15))
            beam.addLine(to: CGPoint(x: c.x - px * half, y: c.y - py * half))
            beam.closeSubpath()
            ctx.fill(beam, with: .color(accent.opacity(0.16 + 0.1 * sin(t * 4 + Double(i)))))
            ctx.fill(beam, with: .color(Color.white.opacity(0.07)))
        }
        if !clearGround {
            ctx.fill(Capsule().path(in: island.insetBy(dx: -16, dy: -14)), with: .color(accent.opacity(0.22)))
            ctx.fill(Capsule().path(in: island.insetBy(dx: -5, dy: -4)), with: .color(Color.white.opacity(0.4 + 0.2 * abs(sin(t * 5)))))
        } else {
            ctx.stroke(Capsule().path(in: island.insetBy(dx: -2, dy: -2)), with: .color(Color.white.opacity(0.35 + 0.2 * abs(sin(t * 5)))), lineWidth: 1.4 * scale)
        }
    }

    static func drawFrost(ctx: GraphicsContext, island: CGRect, t: Double, intensity: CGFloat, scale: CGFloat, clearGround: Bool = false) {
        drawElectric(ctx: ctx, island: island, t: t * 0.65, intensity: intensity * 0.85, scale: scale, clearGround: clearGround)
        for i in 0..<12 {
            let u = frag(Double(i) / 12 + t * 0.04)
            let p = EtubuCutoutGeom.pointOnCapsule(island.insetBy(dx: -5, dy: -5), u: u)
            let ang = atan2(p.y - island.midY, p.x - island.midX)
            let len = (12 + intensity * 10) * scale
            var crystal = Path()
            crystal.move(to: p)
            crystal.addLine(to: CGPoint(x: p.x + cos(ang) * len, y: p.y + sin(ang) * len))
            for branch in [-0.7, 0.7] {
                let mid = CGPoint(x: p.x + cos(ang) * len * 0.55, y: p.y + sin(ang) * len * 0.55)
                crystal.move(to: mid)
                crystal.addLine(to: CGPoint(x: mid.x + cos(ang + branch) * len * 0.35, y: mid.y + sin(ang + branch) * len * 0.35))
            }
            ctx.stroke(crystal, with: .color(Color.cyan.opacity(0.4)), style: StrokeStyle(lineWidth: 2.6 * scale, lineCap: .round))
            ctx.stroke(crystal, with: .color(Color.white.opacity(0.85)), style: StrokeStyle(lineWidth: 1.1 * scale, lineCap: .round))
        }
    }

    static func drawWarp(ctx: GraphicsContext, island: CGRect, t: Double, intensity: CGFloat, scale: CGFloat, accent: Color) {
        let c = CGPoint(x: island.midX, y: island.midY)
        for i in 0..<6 {
            let phase = frag(t * 0.85 + Double(i) * 0.16)
            let r = (6 + CGFloat(phase) * (42 + intensity * 34)) * scale
            let op = (1 - phase) * 0.58
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r * 0.68, width: r * 2, height: r * 1.36)), with: .color(accent.opacity(op)), lineWidth: 2.1 * scale)
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r * 0.9, y: c.y - r * 0.62, width: r * 1.8, height: r * 1.24)), with: .color(Color.white.opacity(op * 0.45)), lineWidth: 0.8 * scale)
        }
    }

    static func drawPlasma(ctx: GraphicsContext, island: CGRect, t: Double, intensity: CGFloat, scale: CGFloat, hue: Double) {
        for ribbon in 0..<4 {
            var path = Path()
            let samples = 40
            for s in 0...samples {
                let u = Double(s) / Double(samples)
                var p = EtubuCutoutGeom.pointOnCapsule(
                    island.insetBy(dx: (-3 - CGFloat(ribbon) * 5) * scale, dy: (-3 - CGFloat(ribbon) * 4) * scale),
                    u: frag(u + t * (0.12 + Double(ribbon) * 0.04))
                )
                let wob = CGFloat(sin(t * 9 + u * 14 + Double(ribbon))) * (6 + intensity * 3) * scale
                p.x += wob; p.y += wob * 0.35
                if s == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            let h = (hue / 360 + Double(ribbon) * 0.05).truncatingRemainder(dividingBy: 1)
            ctx.stroke(path, with: .color(Color(hue: h, saturation: 0.92, brightness: 1).opacity(0.72)), style: StrokeStyle(lineWidth: (3.8 - CGFloat(ribbon) * 0.55) * scale, lineCap: .round))
        }
        if sin(t * 4.5) > 0.72 {
            drawExplosion(ctx: ctx, island: island, t: t * 1.8, intensity: intensity * 0.7, scale: scale * 0.85)
        }
    }

    /// Solar Flare — radial golden corona tongues + bright core.
    static func drawSolarCorona(ctx: GraphicsContext, island: CGRect, t: Double, intensity: CGFloat, scale: CGFloat, clearGround: Bool = false) {
        let c = CGPoint(x: island.midX, y: island.midY)
        if !clearGround {
            ctx.fill(Capsule().path(in: island.insetBy(dx: -8 * scale, dy: -8 * scale)), with: .color(Color.orange.opacity(0.28)))
            ctx.fill(Capsule().path(in: island.insetBy(dx: -3 * scale, dy: -3 * scale)), with: .color(Color.yellow.opacity(0.35 + 0.15 * sin(t * 4))))
        }
        for i in 0..<20 {
            let ang = Double(i) / 20 * .pi * 2 + t * 0.35
            let pulse = 0.65 + 0.35 * sin(t * 5 + Double(i))
            let len = (28 + intensity * 38) * scale * CGFloat(pulse)
            let half = 3.2 * scale * CGFloat(pulse)
            let ax = cos(ang); let ay = sin(ang)
            let px = -ay; let py = ax
            var tongue = Path()
            tongue.move(to: CGPoint(x: c.x + px * half, y: c.y + py * half))
            tongue.addLine(to: CGPoint(x: c.x + ax * len, y: c.y + ay * len))
            tongue.addLine(to: CGPoint(x: c.x - px * half, y: c.y - py * half))
            tongue.closeSubpath()
            ctx.fill(tongue, with: .color(Color(hue: 0.08 + Double(i % 3) * 0.02, saturation: 1, brightness: 1).opacity(0.55)))
            ctx.fill(tongue, with: .color(Color.yellow.opacity(0.25)))
        }
        for i in 0..<12 {
            let ang = Double(i) / 12 * .pi * 2 - t * 1.2
            let dist = (14 + CGFloat((t * 20 + Double(i) * 7).truncatingRemainder(dividingBy: 40))) * scale
            let p = CGPoint(x: c.x + cos(ang) * dist, y: c.y + sin(ang) * dist * 0.85)
            let sz = 1.8 * scale
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - sz, y: p.y - sz, width: sz * 2, height: sz * 2)), with: .color(Color.white.opacity(0.85)))
        }
    }

    /// Violet Storm — purple forked bolts + magenta sparks.
    static func drawVioletStorm(ctx: GraphicsContext, island: CGRect, t: Double, intensity: CGFloat, scale: CGFloat, clearGround: Bool = false) {
        let c = CGPoint(x: island.midX, y: island.midY)
        let violet = Color(hue: 0.78, saturation: 0.95, brightness: 1)
        let magenta = Color(hue: 0.9, saturation: 0.9, brightness: 1)
        if !clearGround {
            ctx.fill(Capsule().path(in: island.insetBy(dx: -7 * scale, dy: -7 * scale)), with: .color(violet.opacity(0.22)))
        }
        let bolts = 9 + Int(intensity * 4)
        for i in 0..<bolts {
            let baseAng = Double(i) / Double(bolts) * .pi * 2 + t * 2.4
            var path = Path()
            var p = EtubuCutoutGeom.pointOnCapsule(island.insetBy(dx: -1, dy: -1), u: frag(baseAng / (.pi * 2)))
            path.move(to: p)
            let reach = (36 + intensity * 48) * scale
            for s in 1...7 {
                let f = CGFloat(s) / 7
                let ang = baseAng + sin(t * 30 + Double(i * 4 + s)) * 0.55
                let jx = CGFloat(sin(t * 50 + Double(i * 9 + s))) * 7 * scale
                let jy = CGFloat(cos(t * 42 + Double(i * 7 + s))) * 7 * scale
                p = CGPoint(x: c.x + cos(ang) * reach * f + jx, y: c.y + sin(ang) * reach * f + jy)
                path.addLine(to: p)
            }
            ctx.stroke(path, with: .color(violet.opacity(0.35)), style: StrokeStyle(lineWidth: 6 * scale, lineCap: .round))
            ctx.stroke(path, with: .color(magenta.opacity(0.85)), style: StrokeStyle(lineWidth: 2.2 * scale, lineCap: .round))
            ctx.stroke(path, with: .color(Color.white.opacity(0.75)), style: StrokeStyle(lineWidth: 0.9 * scale, lineCap: .round))
        }
    }

    /// Deep Ocean — concentric wave rings + bubble drift.
    static func drawOceanWave(ctx: GraphicsContext, island: CGRect, t: Double, intensity: CGFloat, scale: CGFloat, accent: Color, clearGround: Bool = false) {
        let c = CGPoint(x: island.midX, y: island.midY)
        if !clearGround {
            ctx.fill(Capsule().path(in: island.insetBy(dx: -6 * scale, dy: -6 * scale)), with: .color(accent.opacity(0.25)))
        }
        for i in 0..<7 {
            let phase = frag(t * 0.55 + Double(i) * 0.14)
            let r = (8 + CGFloat(phase) * (38 + intensity * 28)) * scale
            let op = (1 - phase) * 0.55
            ctx.stroke(
                Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r * 0.72, width: r * 2, height: r * 1.44)),
                with: .color(accent.opacity(op)),
                lineWidth: 2.0 * scale
            )
            ctx.stroke(
                Path(ellipseIn: CGRect(x: c.x - r * 0.92, y: c.y - r * 0.66, width: r * 1.84, height: r * 1.32)),
                with: .color(Color.cyan.opacity(op * 0.45)),
                lineWidth: 0.8 * scale
            )
        }
        for i in 0..<14 {
            let ang = Double(i) / 14 * .pi * 2 + t * 0.4
            let rise = CGFloat((t * 14 + Double(i) * 11).truncatingRemainder(dividingBy: 50))
            let p = CGPoint(
                x: c.x + cos(ang) * (12 + rise * 0.35) * scale,
                y: c.y + sin(ang) * (10 + rise * 0.3) * scale - rise * 0.15 * scale
            )
            let life = max(0, 1 - rise / 50)
            let sz = (1.5 + intensity * 0.5) * scale * life
            ctx.stroke(Path(ellipseIn: CGRect(x: p.x - sz, y: p.y - sz, width: sz * 2, height: sz * 2)), with: .color(Color.white.opacity(0.55 * life)), lineWidth: 0.8 * scale)
        }
    }

    /// Tunnel — perspective dashed speed lines rushing past the pill.
    static func drawTunnelLines(ctx: GraphicsContext, island: CGRect, t: Double, intensity: CGFloat, scale: CGFloat, accent: Color, clearGround: Bool = false) {
        let c = CGPoint(x: island.midX, y: island.midY)
        if !clearGround {
            ctx.fill(Capsule().path(in: island.insetBy(dx: -5 * scale, dy: -5 * scale)), with: .color(accent.opacity(0.2)))
        }
        let lines = 16 + Int(intensity * 6)
        for i in 0..<lines {
            let ang = Double(i) / Double(lines) * .pi * 2
            let dash = frag(t * 1.8 + Double(i) * 0.07)
            let inner = (6 + CGFloat(dash) * 8) * scale
            let outer = (22 + intensity * 40 + CGFloat(dash) * 28) * scale
            var path = Path()
            path.move(to: CGPoint(x: c.x + cos(ang) * inner, y: c.y + sin(ang) * inner * 0.85))
            path.addLine(to: CGPoint(x: c.x + cos(ang) * outer, y: c.y + sin(ang) * outer * 0.85))
            let op = 0.25 + 0.55 * (1 - dash)
            ctx.stroke(path, with: .color(accent.opacity(op)), style: StrokeStyle(lineWidth: (1.2 + intensity * 0.6) * scale, lineCap: .round))
            ctx.stroke(path, with: .color(Color.white.opacity(op * 0.45)), style: StrokeStyle(lineWidth: 0.6 * scale, lineCap: .round))
        }
        // Inner racing ring
        let ringR = (10 + abs(sin(t * 3)) * 4) * scale
        ctx.stroke(
            Path(ellipseIn: CGRect(x: c.x - ringR, y: c.y - ringR * 0.7, width: ringR * 2, height: ringR * 1.4)),
            with: .color(accent.opacity(0.65)),
            lineWidth: 1.6 * scale
        )
    }

    static func frag(_ x: Double) -> Double {
        let v = x.truncatingRemainder(dividingBy: 1)
        return v < 0 ? v + 1 : v
    }
}

/// Capsule perimeter sampling — supports horizontal and vertical pills.
enum EtubuCutoutGeom {
    static func pointOnCapsule(_ rect: CGRect, u: Double) -> CGPoint {
        let uu = EtubuCutoutFX.frag(u)
        let r = min(rect.width, rect.height) / 2
        if rect.width >= rect.height {
            let straight = max(0, rect.width - 2 * r)
            let peri = 2 * straight + 2 * .pi * r
            var d = CGFloat(uu) * peri
            if d <= straight { return CGPoint(x: rect.minX + r + d, y: rect.minY) }
            d -= straight
            if d <= .pi * r {
                let a = -CGFloat.pi / 2 + d / r
                return CGPoint(x: rect.maxX - r + cos(a) * r, y: rect.midY + sin(a) * r)
            }
            d -= .pi * r
            if d <= straight { return CGPoint(x: rect.maxX - r - d, y: rect.maxY) }
            d -= straight
            let a = CGFloat.pi / 2 + d / r
            return CGPoint(x: rect.minX + r + cos(a) * r, y: rect.midY + sin(a) * r)
        } else {
            let straight = max(0, rect.height - 2 * r)
            let peri = 2 * straight + 2 * .pi * r
            var d = CGFloat(uu) * peri
            // right edge top→bottom
            if d <= straight { return CGPoint(x: rect.maxX, y: rect.minY + r + d) }
            d -= straight
            // bottom semicircle
            if d <= .pi * r {
                let a = d / r
                return CGPoint(x: rect.midX + sin(a) * r, y: rect.maxY - r + cos(a) * r)
            }
            d -= .pi * r
            // left edge bottom→top
            if d <= straight { return CGPoint(x: rect.minX, y: rect.maxY - r - d) }
            d -= straight
            let a = d / r
            return CGPoint(x: rect.midX - sin(a) * r, y: rect.minY + r - cos(a) * r)
        }
    }
}

