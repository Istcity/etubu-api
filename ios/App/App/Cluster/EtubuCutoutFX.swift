import SwiftUI

/// Named cutout FX library — each kind has a Turkish title matching the reference art.
enum EtubuCutoutFX: String, CaseIterable, Identifiable {
    case elektrik
    case ates
    case duman
    case patlama
    case isikHuzmesi
    case buzKristali
    case warpHalka
    case plazma

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
        }
    }

    static func forTheme(_ theme: ClusterTheme) -> EtubuCutoutFX {
        switch theme {
        case .cyberLime: return .elektrik
        case .electricIce: return .buzKristali
        case .solarFlare, .redline: return .ates
        case .midnight, .tunnel: return .duman
        case .neon: return .patlama
        case .plasma, .violetStorm: return .plazma
        case .aurora, .deepOcean: return .isikHuzmesi
        case .warp: return .warpHalka
        }
    }

    func draw(
        ctx: GraphicsContext,
        island: CGRect,
        t: Double,
        intensity: CGFloat,
        accent: Color,
        hue: Double
    ) {
        let scale = max(0.85, min(1.4, max(island.width, island.height) / 126))
        switch self {
        case .elektrik: Self.drawElectric(ctx: ctx, island: island, t: t, intensity: intensity, scale: scale)
        case .ates: Self.drawFire(ctx: ctx, island: island, t: t, intensity: intensity, scale: scale)
        case .duman: Self.drawSmoke(ctx: ctx, island: island, t: t, intensity: intensity, scale: scale)
        case .patlama: Self.drawExplosion(ctx: ctx, island: island, t: t, intensity: intensity, scale: scale)
        case .isikHuzmesi: Self.drawBeam(ctx: ctx, island: island, t: t, intensity: intensity, scale: scale, accent: accent)
        case .buzKristali: Self.drawFrost(ctx: ctx, island: island, t: t, intensity: intensity, scale: scale)
        case .warpHalka: Self.drawWarp(ctx: ctx, island: island, t: t, intensity: intensity, scale: scale, accent: accent)
        case .plazma: Self.drawPlasma(ctx: ctx, island: island, t: t, intensity: intensity, scale: scale, hue: hue)
        }
    }
}

// MARK: - Drawing (realistic particle / field FX)

private extension EtubuCutoutFX {

    /// Branched lightning bolts radiating from the pill — blue/white core.
    static func drawElectric(ctx: GraphicsContext, island: CGRect, t: Double, intensity: CGFloat, scale: CGFloat) {
        let c = CGPoint(x: island.midX, y: island.midY)
        ctx.fill(Capsule().path(in: island.insetBy(dx: -5, dy: -5)), with: .color(Color.cyan.opacity(0.18 + 0.1 * abs(sin(t * 9)))))

        let bolts = 8 + Int(intensity * 5)
        for i in 0..<bolts {
            let baseAng = Double(i) / Double(bolts) * .pi * 2 + t * (1.8 + Double(intensity) * 0.6)
            var path = Path()
            var p = EtubuCutoutGeom.pointOnCapsule(island.insetBy(dx: -1, dy: -1), u: frag(baseAng / (.pi * 2)))
            path.move(to: p)
            let segs = 6 + Int(intensity * 2)
            let reach = (32 + intensity * 42) * scale
            for s in 1...segs {
                let f = CGFloat(s) / CGFloat(segs)
                let ang = baseAng + sin(t * 26 + Double(i * 5 + s)) * 0.42
                // Fork mid-bolt
                if s == segs / 2 {
                    var fork = Path()
                    fork.move(to: p)
                    let fang = ang + (i % 2 == 0 ? 0.55 : -0.55)
                    let fp = CGPoint(
                        x: p.x + cos(fang) * reach * 0.35,
                        y: p.y + sin(fang) * reach * 0.35
                    )
                    fork.addLine(to: fp)
                    strokeBolt(ctx: ctx, path: fork, scale: scale, hot: false)
                }
                let jx = CGFloat(sin(t * 48 + Double(i * 13 + s * 7))) * (5 + intensity * 4) * scale
                let jy = CGFloat(cos(t * 41 + Double(i * 11 + s))) * (5 + intensity * 4) * scale
                p = CGPoint(x: c.x + cos(ang) * reach * f + jx, y: c.y + sin(ang) * reach * f + jy)
                path.addLine(to: p)
            }
            strokeBolt(ctx: ctx, path: path, scale: scale, hot: i % 3 == 0)
        }

        // White-hot tips
        for i in 0..<10 {
            let u = frag(t * 0.7 + Double(i) / 10)
            let p = EtubuCutoutGeom.pointOnCapsule(island.insetBy(dx: -7 * scale, dy: -7 * scale), u: u)
            let r = (1.6 + intensity * 0.7) * scale
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 2, y: p.y - r * 2, width: r * 4, height: r * 4)), with: .color(Color.cyan.opacity(0.35)))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(Color.white.opacity(0.95)))
        }
    }

    static func strokeBolt(ctx: GraphicsContext, path: Path, scale: CGFloat, hot: Bool) {
        ctx.stroke(path, with: .color(Color.cyan.opacity(0.28)), style: StrokeStyle(lineWidth: 6.5 * scale, lineCap: .round, lineJoin: .round))
        ctx.stroke(path, with: .color(Color(red: 0.45, green: 0.85, blue: 1).opacity(0.85)), style: StrokeStyle(lineWidth: 2.4 * scale, lineCap: .round, lineJoin: .round))
        ctx.stroke(path, with: .color(Color.white.opacity(hot ? 0.95 : 0.7)), style: StrokeStyle(lineWidth: (hot ? 1.2 : 0.8) * scale, lineCap: .round, lineJoin: .round))
    }

    /// Flame ring wrapping the pill + rising tongues + embers (reference Ateş).
    static func drawFire(ctx: GraphicsContext, island: CGRect, t: Double, intensity: CGFloat, scale: CGFloat) {
        let ring = island.insetBy(dx: -6 * scale, dy: -8 * scale)
        for i in 0..<18 {
            let u = frag(Double(i) / 18 + t * 0.1)
            let base = EtubuCutoutGeom.pointOnCapsule(ring, u: u)
            let outward = CGPoint(x: base.x - island.midX, y: base.y - island.midY)
            let len = max(1, hypot(outward.x, outward.y))
            let nx = outward.x / len
            let ny = outward.y / len
            let rise = CGFloat((t * (20 + Double(i % 5) * 5) + Double(i) * 6).truncatingRemainder(dividingBy: 50))
            let flicker = CGFloat(sin(t * 16 + Double(i) * 1.7)) * 4 * scale
            let tip = CGPoint(
                x: base.x + nx * (14 + rise * 0.65) * scale + ny * flicker,
                y: base.y + ny * (14 + rise * 0.65) * scale - nx * flicker * 0.4
            )
            var flame = Path()
            let side = 5.5 * scale
            flame.move(to: CGPoint(x: base.x - ny * side, y: base.y + nx * side))
            flame.addQuadCurve(to: tip, control: CGPoint(x: base.x + nx * 8 * scale - ny * side * 0.3, y: base.y + ny * 8 * scale + nx * side * 0.3))
            flame.addQuadCurve(to: CGPoint(x: base.x + ny * side, y: base.y - nx * side), control: CGPoint(x: tip.x + ny * 2, y: tip.y - nx * 2))
            flame.closeSubpath()
            let life = max(0.12, 1 - rise / 52)
            ctx.fill(flame, with: .color(Color(hue: 0.05 + Double(i % 3) * 0.015, saturation: 1, brightness: 1).opacity(0.5 * life * Double(intensity))))
            ctx.fill(
                Path(ellipseIn: CGRect(x: tip.x - 2.2 * scale, y: tip.y - 2.2 * scale, width: 4.4 * scale, height: 4.4 * scale)),
                with: .color(Color.yellow.opacity(0.75 * life))
            )
        }
        // Ember particles drifting out
        for i in 0..<16 {
            let ang = Double(i) / 16 * .pi * 2 + t * 1.35
            let dist = (18 + CGFloat((t * 28 + Double(i) * 9).truncatingRemainder(dividingBy: 48))) * scale
            let p = CGPoint(x: island.midX + cos(ang) * dist, y: island.midY + sin(ang) * dist * 0.9)
            let life = max(0, 1 - (dist / scale - 18) / 48)
            let sz = (1.2 + intensity * 0.6) * scale * life
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - sz, y: p.y - sz, width: sz * 2, height: sz * 2)), with: .color(Color.orange.opacity(0.85 * life)))
        }
        ctx.stroke(Capsule().path(in: island.insetBy(dx: -2, dy: -2)), with: .color(Color.orange.opacity(0.55 + 0.2 * sin(t * 5))), lineWidth: 2.4 * scale)
        ctx.fill(Capsule().path(in: island.insetBy(dx: -3, dy: -3)), with: .color(Color(hue: 0.07, saturation: 1, brightness: 1).opacity(0.12)))
    }

    /// Dense dark billows expanding from the cutout (reference Duman).
    static func drawSmoke(ctx: GraphicsContext, island: CGRect, t: Double, intensity: CGFloat, scale: CGFloat) {
        for i in 0..<18 {
            let u = frag(Double(i) / 18 + t * 0.035)
            let base = EtubuCutoutGeom.pointOnCapsule(island.insetBy(dx: -2, dy: -2), u: u)
            let rise = CGFloat((t * (9 + Double(i % 5) * 2.5) + Double(i) * 13).truncatingRemainder(dividingBy: 100))
            let sway = sin(t * 0.95 + Double(i) * 0.7) * (12 + rise * 0.14) * scale
            let x = base.x + sway
            let y = base.y - rise * 0.5 * scale + cos(t * 0.8 + Double(i)) * 5 * scale
            let r = (12 + rise * 0.28 + intensity * 5) * scale
            let life = max(0, 1 - rise / 100)
            let gray = 0.08 + Double(i % 4) * 0.04
            ctx.fill(
                Path(ellipseIn: CGRect(x: x - r, y: y - r * 0.8, width: r * 2.1, height: r * 1.6)),
                with: .color(Color(white: gray).opacity(0.5 * life))
            )
            ctx.fill(
                Path(ellipseIn: CGRect(x: x - r * 0.45, y: y - r * 0.35, width: r * 0.9, height: r * 0.7)),
                with: .color(Color.white.opacity(0.05 * life))
            )
        }
        ctx.fill(Capsule().path(in: island.insetBy(dx: -8, dy: -7)), with: .color(Color.black.opacity(0.42)))
    }

    /// Cinematic blast — white core, orange shell, flying sparks (reference Patlama).
    static func drawExplosion(ctx: GraphicsContext, island: CGRect, t: Double, intensity: CGFloat, scale: CGFloat) {
        let pulse = (t * 0.65).truncatingRemainder(dividingBy: 1)
        let blast = 1 - pow(1 - min(1, max(0, pulse)), 2.4)
        let c = CGPoint(x: island.midX, y: island.midY)

        for k in 0..<4 {
            let expand = (10 + CGFloat(blast) * (48 + intensity * 32) + CGFloat(k) * 12) * scale
            let op = max(0, (0.6 - Double(k) * 0.12) * (1 - blast))
            ctx.stroke(
                Path(ellipseIn: CGRect(x: c.x - expand, y: c.y - expand * 0.75, width: expand * 2, height: expand * 1.5)),
                with: .color(Color.orange.opacity(op)),
                lineWidth: (3.2 - CGFloat(k) * 0.55) * scale
            )
        }

        let coreR = (10 + CGFloat(blast) * 22 * intensity) * scale
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - coreR * 2.2, y: c.y - coreR * 1.5, width: coreR * 4.4, height: coreR * 3)), with: .color(Color.orange.opacity(0.3 * (1 - blast))))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - coreR * 1.5, y: c.y - coreR, width: coreR * 3, height: coreR * 2)), with: .color(Color.yellow.opacity(0.5 * (1 - blast))))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - coreR, y: c.y - coreR * 0.7, width: coreR * 2, height: coreR * 1.4)), with: .color(Color.white.opacity(0.9 * (1 - blast * 0.65))))

        let sparkN = 22 + Int(intensity * 10)
        for i in 0..<sparkN {
            let ang = Double(i) / Double(sparkN) * .pi * 2 + t * 0.25
            let dist = CGFloat(blast) * (40 + intensity * 48) * scale * (0.45 + CGFloat((i * 19) % 11) / 11)
            let p = CGPoint(x: c.x + cos(ang) * dist, y: c.y + sin(ang) * dist * 0.85)
            let life = max(0, 1 - blast)
            let sz = (1.4 + intensity * 0.9) * scale
            // Streak
            var streak = Path()
            streak.move(to: CGPoint(x: p.x - cos(ang) * sz * 3, y: p.y - sin(ang) * sz * 3))
            streak.addLine(to: p)
            ctx.stroke(streak, with: .color(Color.orange.opacity(0.7 * life)), style: StrokeStyle(lineWidth: sz * 0.7, lineCap: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - sz, y: p.y - sz, width: sz * 2, height: sz * 2)), with: .color(Color.white.opacity(0.9 * life)))
        }
        ctx.stroke(Capsule().path(in: island), with: .color(Color.white.opacity(0.45 + 0.45 * (1 - blast))), lineWidth: 1.6 * scale)
    }

    static func drawBeam(ctx: GraphicsContext, island: CGRect, t: Double, intensity: CGFloat, scale: CGFloat, accent: Color) {
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
        ctx.fill(Capsule().path(in: island.insetBy(dx: -16, dy: -14)), with: .color(accent.opacity(0.22)))
        ctx.fill(Capsule().path(in: island.insetBy(dx: -5, dy: -4)), with: .color(Color.white.opacity(0.4 + 0.2 * abs(sin(t * 5)))))
    }

    static func drawFrost(ctx: GraphicsContext, island: CGRect, t: Double, intensity: CGFloat, scale: CGFloat) {
        drawElectric(ctx: ctx, island: island, t: t * 0.65, intensity: intensity * 0.85, scale: scale)
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
