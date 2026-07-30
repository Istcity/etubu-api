import SwiftUI

/// Camera-cutout / Dynamic Island aura — theme-locked FX matching reference art.
/// Effects: electric · fire · smoke · explosion · beam · frost · warp · plasma
struct EtubuNotchAuraView: View {
    let kmh: Int
    let theme: ClusterTheme
    let width: CGFloat

    private var intensity: CGFloat {
        min(1.85, 0.55 + CGFloat(kmh) / 95)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 28, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let island = islandRect(in: size)
                // Soft vignette behind FX so cutout reads as “alive”
                ctx.fill(
                    Capsule().path(in: island.insetBy(dx: -10, dy: -8)),
                    with: .color(theme.accent.opacity(0.08 + 0.04 * sin(t * 3)))
                )

                switch theme.notchAura {
                case .electric:
                    drawElectric(ctx: ctx, island: island, size: size, t: t)
                case .fire:
                    drawFire(ctx: ctx, island: island, size: size, t: t)
                case .smoke:
                    drawSmoke(ctx: ctx, island: island, size: size, t: t)
                case .explosion:
                    drawExplosion(ctx: ctx, island: island, size: size, t: t)
                case .beam:
                    drawBeam(ctx: ctx, island: island, size: size, t: t)
                case .frost:
                    drawFrost(ctx: ctx, island: island, size: size, t: t)
                case .warp:
                    drawWarp(ctx: ctx, island: island, size: size, t: t)
                case .plasma:
                    drawPlasma(ctx: ctx, island: island, size: size, t: t)
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// Pill aligned to camera / Dynamic Island in the side safe-area strip.
    private func islandRect(in size: CGSize) -> CGRect {
        let w = min(max(width * 0.78, 96), 132)
        let h: CGFloat = 36
        let x = (size.width - w) / 2
        let y = (size.height - h) / 2
        return CGRect(x: x, y: y, width: w, height: h)
    }

    // MARK: - Electric (reference: blue bolts radiating)

    private func drawElectric(ctx: GraphicsContext, island: CGRect, size: CGSize, t: Double) {
        let c = CGPoint(x: island.midX, y: island.midY)
        let boltCount = 7 + Int(intensity * 4)
        for i in 0..<boltCount {
            let baseAng = Double(i) / Double(boltCount) * .pi * 2 + t * (1.6 + Double(intensity))
            var path = Path()
            var p = pointOnCapsule(island.insetBy(dx: -2, dy: -2), u: (baseAng / (.pi * 2)).truncatingRemainder(dividingBy: 1))
            path.move(to: p)
            let segs = 5 + Int(intensity * 2)
            let reach = 28 + intensity * 36
            for s in 1...segs {
                let f = CGFloat(s) / CGFloat(segs)
                let ang = baseAng + sin(t * 22 + Double(i * 3 + s)) * 0.35
                let jx = CGFloat(sin(t * 40 + Double(i * 11 + s * 7))) * (4 + intensity * 3)
                let jy = CGFloat(cos(t * 37 + Double(i * 9 + s))) * (4 + intensity * 3)
                p = CGPoint(
                    x: c.x + cos(ang) * reach * f + jx,
                    y: c.y + sin(ang) * reach * f + jy
                )
                path.addLine(to: p)
            }
            let cyan = Color(hue: 0.55, saturation: 0.95, brightness: 1)
            let white = Color.white
            ctx.stroke(path, with: .color(cyan.opacity(0.35)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            ctx.stroke(path, with: .color(cyan.opacity(0.85)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            ctx.stroke(path, with: .color(white.opacity(0.9)), style: StrokeStyle(lineWidth: 0.9, lineCap: .round))
        }
        // Core flash
        ctx.fill(
            Capsule().path(in: island.insetBy(dx: -4, dy: -4)),
            with: .color(Color.cyan.opacity(0.2 + 0.15 * abs(sin(t * 8))))
        )
        orbitSparks(ctx: ctx, island: island, t: t, count: 10, color: .white, accent: Color.cyan)
    }

    // MARK: - Fire (reference: flame ring + embers)

    private func drawFire(ctx: GraphicsContext, island: CGRect, size: CGSize, t: Double) {
        let ring = island.insetBy(dx: -8, dy: -10)
        for i in 0..<16 {
            let u = (Double(i) / 16.0 + t * 0.08).truncatingRemainder(dividingBy: 1)
            let base = pointOnCapsule(ring, u: u)
            let outward = CGPoint(x: base.x - island.midX, y: base.y - island.midY)
            let len = max(1, hypot(outward.x, outward.y))
            let nx = outward.x / len
            let ny = outward.y / len
            let rise = CGFloat((t * (18 + Double(i % 5) * 4) + Double(i) * 5).truncatingRemainder(dividingBy: 42))
            let flicker = CGFloat(sin(t * 14 + Double(i))) * 3
            let tip = CGPoint(
                x: base.x + nx * (12 + rise * 0.55) + flicker,
                y: base.y + ny * (12 + rise * 0.55) - abs(flicker) * 0.3
            )
            var flame = Path()
            flame.move(to: CGPoint(x: base.x - ny * 4, y: base.y + nx * 4))
            flame.addLine(to: tip)
            flame.addLine(to: CGPoint(x: base.x + ny * 4, y: base.y - nx * 4))
            flame.closeSubpath()
            let life = max(0.15, 1 - rise / 45)
            let hue = 0.04 + Double(i % 4) * 0.02
            ctx.fill(flame, with: .color(Color(hue: hue, saturation: 1, brightness: 1).opacity(0.55 * life * Double(intensity))))
            ctx.fill(
                Path(ellipseIn: CGRect(x: tip.x - 2.5, y: tip.y - 2.5, width: 5, height: 5)),
                with: .color(Color.yellow.opacity(0.7 * life))
            )
        }
        // Embers
        for i in 0..<12 {
            let ang = Double(i) / 12 * .pi * 2 + t * 1.2
            let r = 22 + CGFloat((t * 30 + Double(i) * 7).truncatingRemainder(dividingBy: 40))
            let p = CGPoint(x: island.midX + cos(ang) * r, y: island.midY + sin(ang) * r * 0.85)
            let life = max(0, 1 - (r - 22) / 40)
            ctx.fill(
                Path(ellipseIn: CGRect(x: p.x - 1.5, y: p.y - 1.5, width: 3, height: 3)),
                with: .color(Color.orange.opacity(0.8 * life))
            )
        }
        ctx.stroke(
            Capsule().path(in: island.insetBy(dx: -3, dy: -3)),
            with: .color(Color.orange.opacity(0.55 + 0.2 * sin(t * 6))),
            lineWidth: 2.5
        )
    }

    // MARK: - Smoke (reference: thick dark billows)

    private func drawSmoke(ctx: GraphicsContext, island: CGRect, size: CGSize, t: Double) {
        for i in 0..<14 {
            let u = (Double(i) / 14 + t * 0.04).truncatingRemainder(dividingBy: 1)
            let base = pointOnCapsule(island.insetBy(dx: -2, dy: -2), u: u)
            let rise = CGFloat((t * (10 + Double(i % 4) * 3) + Double(i) * 11).truncatingRemainder(dividingBy: 90))
            let sway = sin(t * 1.1 + Double(i)) * (10 + rise * 0.12)
            let x = base.x + sway
            let y = base.y - rise * 0.55 + cos(t + Double(i)) * 4
            let r: CGFloat = 10 + rise * 0.22 + intensity * 4
            let life = max(0, 1 - rise / 90)
            let dark = Color(white: 0.12 + Double(i % 3) * 0.05)
            ctx.fill(
                Path(ellipseIn: CGRect(x: x - r, y: y - r * 0.75, width: r * 2, height: r * 1.5)),
                with: .color(dark.opacity(0.45 * life))
            )
            ctx.fill(
                Path(ellipseIn: CGRect(x: x - r * 0.5, y: y - r * 0.4, width: r, height: r * 0.8)),
                with: .color(Color.white.opacity(0.04 * life))
            )
        }
        ctx.fill(
            Capsule().path(in: island.insetBy(dx: -6, dy: -5)),
            with: .color(Color.black.opacity(0.35))
        )
    }

    // MARK: - Explosion (reference: white core + orange blast + sparks)

    private func drawExplosion(ctx: GraphicsContext, island: CGRect, size: CGSize, t: Double) {
        // Pulse every ~1.4s
        let pulse = (t * 0.72).truncatingRemainder(dividingBy: 1)
        let blast = easeOut(pulse)
        let c = CGPoint(x: island.midX, y: island.midY)

        // Shock rings
        for k in 0..<3 {
            let expand = 12 + CGFloat(blast) * (40 + intensity * 28) + CGFloat(k) * 10
            let op = max(0, (0.55 - Double(k) * 0.12) * (1 - blast))
            ctx.stroke(
                Path(ellipseIn: CGRect(x: c.x - expand, y: c.y - expand * 0.72, width: expand * 2, height: expand * 1.44)),
                with: .color(Color.orange.opacity(op)),
                lineWidth: 3 - CGFloat(k) * 0.6
            )
        }

        // Core flash
        let coreR = 8 + CGFloat(blast) * 18 * intensity
        ctx.fill(
            Path(ellipseIn: CGRect(x: c.x - coreR, y: c.y - coreR * 0.7, width: coreR * 2, height: coreR * 1.4)),
            with: .color(Color.white.opacity(0.85 * (1 - blast * 0.7)))
        )
        ctx.fill(
            Path(ellipseIn: CGRect(x: c.x - coreR * 1.4, y: c.y - coreR, width: coreR * 2.8, height: coreR * 2)),
            with: .color(Color.yellow.opacity(0.45 * (1 - blast)))
        )
        ctx.fill(
            Path(ellipseIn: CGRect(x: c.x - coreR * 2, y: c.y - coreR * 1.3, width: coreR * 4, height: coreR * 2.6)),
            with: .color(Color.orange.opacity(0.28 * (1 - blast)))
        )

        // Flying sparks
        let sparkN = 18 + Int(intensity * 8)
        for i in 0..<sparkN {
            let ang = Double(i) / Double(sparkN) * .pi * 2 + t * 0.3
            let dist = CGFloat(blast) * (35 + intensity * 40) * (0.55 + CGFloat((i * 17) % 10) / 10)
            let p = CGPoint(x: c.x + cos(ang) * dist, y: c.y + sin(ang) * dist * 0.8)
            let life = max(0, 1 - blast)
            let sz: CGFloat = 1.5 + intensity * 0.8
            ctx.fill(
                Path(ellipseIn: CGRect(x: p.x - sz, y: p.y - sz, width: sz * 2, height: sz * 2)),
                with: .color(Color(hue: 0.08, saturation: 1, brightness: 1).opacity(0.9 * life))
            )
        }

        ctx.stroke(
            Capsule().path(in: island),
            with: .color(Color.white.opacity(0.5 + 0.4 * (1 - blast))),
            lineWidth: 1.5
        )
    }

    // MARK: - Light beam (ışık hüzmesi)

    private func drawBeam(ctx: GraphicsContext, island: CGRect, size: CGSize, t: Double) {
        let c = CGPoint(x: island.midX, y: island.midY)
        for i in 0..<8 {
            let ang = Double(i) / 8 * .pi * 2 + t * 0.35
            let len = 50 + intensity * 40 + CGFloat(sin(t * 3 + Double(i))) * 10
            let half: CGFloat = 3 + intensity * 2
            var beam = Path()
            let ax = cos(ang)
            let ay = sin(ang)
            let px = -ay
            let py = ax
            beam.move(to: CGPoint(x: c.x + px * half, y: c.y + py * half))
            beam.addLine(to: CGPoint(x: c.x + ax * len + px * half * 0.2, y: c.y + ay * len + py * half * 0.2))
            beam.addLine(to: CGPoint(x: c.x + ax * len - px * half * 0.2, y: c.y + ay * len - py * half * 0.2))
            beam.addLine(to: CGPoint(x: c.x - px * half, y: c.y - py * half))
            beam.closeSubpath()
            ctx.fill(beam, with: .color(theme.accent.opacity(0.14 + 0.08 * sin(t * 4 + Double(i)))))
            ctx.fill(beam, with: .color(Color.white.opacity(0.06)))
        }
        ctx.fill(
            Capsule().path(in: island.insetBy(dx: -5, dy: -4)),
            with: .color(Color.white.opacity(0.35 + 0.2 * abs(sin(t * 5))))
        )
        ctx.fill(
            Capsule().path(in: island.insetBy(dx: -14, dy: -12)),
            with: .color(theme.accent.opacity(0.2))
        )
    }

    // MARK: - Frost (extra)

    private func drawFrost(ctx: GraphicsContext, island: CGRect, size: CGSize, t: Double) {
        drawElectric(ctx: ctx, island: island, size: size, t: t * 0.7)
        for i in 0..<10 {
            let u = (Double(i) / 10 + t * 0.05).truncatingRemainder(dividingBy: 1)
            let p = pointOnCapsule(island.insetBy(dx: -6, dy: -6), u: u)
            let ang = atan2(p.y - island.midY, p.x - island.midX)
            var crystal = Path()
            let len: CGFloat = 10 + intensity * 8
            crystal.move(to: p)
            crystal.addLine(to: CGPoint(x: p.x + cos(ang) * len, y: p.y + sin(ang) * len))
            crystal.move(to: CGPoint(x: p.x + cos(ang) * len * 0.5 + cos(ang + 0.9) * 4, y: p.y + sin(ang) * len * 0.5 + sin(ang + 0.9) * 4))
            crystal.addLine(to: CGPoint(x: p.x + cos(ang) * len * 0.5 + cos(ang - 0.9) * 4, y: p.y + sin(ang) * len * 0.5 + sin(ang - 0.9) * 4))
            ctx.stroke(crystal, with: .color(Color.white.opacity(0.75)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            ctx.stroke(crystal, with: .color(Color.cyan.opacity(0.45)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
    }

    // MARK: - Warp rings (extra)

    private func drawWarp(ctx: GraphicsContext, island: CGRect, size: CGSize, t: Double) {
        let c = CGPoint(x: island.midX, y: island.midY)
        for i in 0..<5 {
            let phase = (t * 0.9 + Double(i) * 0.2).truncatingRemainder(dividingBy: 1)
            let r = 8 + CGFloat(phase) * (38 + intensity * 30)
            let op = (1 - phase) * 0.55
            ctx.stroke(
                Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r * 0.65, width: r * 2, height: r * 1.3)),
                with: .color(theme.accent.opacity(op)),
                lineWidth: 2
            )
            ctx.stroke(
                Path(ellipseIn: CGRect(x: c.x - r * 0.92, y: c.y - r * 0.6, width: r * 1.84, height: r * 1.2)),
                with: .color(Color.white.opacity(op * 0.5)),
                lineWidth: 0.8
            )
        }
        orbitSparks(ctx: ctx, island: island, t: t, count: 8, color: .white, accent: theme.accent)
    }

    // MARK: - Plasma ribbon (extra)

    private func drawPlasma(ctx: GraphicsContext, island: CGRect, size: CGSize, t: Double) {
        for ribbon in 0..<3 {
            var path = Path()
            let samples = 36
            for s in 0...samples {
                let u = Double(s) / Double(samples)
                var p = pointOnCapsule(island.insetBy(dx: -4 - CGFloat(ribbon) * 5, dy: -4 - CGFloat(ribbon) * 4), u: (u + t * (0.15 + Double(ribbon) * 0.05)).truncatingRemainder(dividingBy: 1))
                let wob = CGFloat(sin(t * 8 + u * 12 + Double(ribbon))) * (5 + intensity * 3)
                p.x += wob
                p.y += wob * 0.4
                if s == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            let hue = (theme.hue / 360 + Double(ribbon) * 0.06).truncatingRemainder(dividingBy: 1)
            ctx.stroke(
                path,
                with: .color(Color(hue: hue, saturation: 0.9, brightness: 1).opacity(0.7)),
                style: StrokeStyle(lineWidth: 3.5 - CGFloat(ribbon), lineCap: .round)
            )
        }
        // Occasional micro-bursts
        if sin(t * 5) > 0.7 {
            drawExplosion(ctx: ctx, island: island, size: size, t: t * 2)
        }
    }

    // MARK: - Shared

    private func orbitSparks(ctx: GraphicsContext, island: CGRect, t: Double, count: Int, color: Color, accent: Color) {
        for i in 0..<count {
            let u = (t * 0.55 + Double(i) / Double(count)).truncatingRemainder(dividingBy: 1)
            let p = pointOnCapsule(island.insetBy(dx: -8, dy: -8), u: u)
            let r: CGFloat = 1.8 + intensity * 0.6
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r - 2, y: p.y - r - 2, width: (r + 2) * 2, height: (r + 2) * 2)), with: .color(accent.opacity(0.4)))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(color.opacity(0.95)))
        }
    }

    private func easeOut(_ x: Double) -> Double {
        1 - pow(1 - min(1, max(0, x)), 3)
    }

    private func pointOnCapsule(_ rect: CGRect, u: Double) -> CGPoint {
        let uu = u.truncatingRemainder(dividingBy: 1)
        let r = min(rect.width, rect.height) / 2
        let straight = max(0, rect.width - 2 * r)
        let peri = 2 * straight + 2 * .pi * r
        var d = CGFloat(uu) * peri
        if d <= straight {
            return CGPoint(x: rect.minX + r + d, y: rect.minY)
        }
        d -= straight
        if d <= .pi * r {
            let a = -CGFloat.pi / 2 + d / r
            return CGPoint(x: rect.maxX - r + cos(a) * r, y: rect.midY + sin(a) * r)
        }
        d -= .pi * r
        if d <= straight {
            return CGPoint(x: rect.maxX - r - d, y: rect.maxY)
        }
        d -= straight
        let a = CGFloat.pi / 2 + d / r
        return CGPoint(x: rect.minX + r + cos(a) * r, y: rect.midY + sin(a) * r)
    }
}

// MARK: - Theme → aura mapping

extension ClusterTheme {
    enum NotchAuraKind {
        case electric, fire, smoke, explosion, beam, frost, warp, plasma
    }

    /// Each theme locks to one cutout FX (reference + extras).
    var notchAura: NotchAuraKind {
        switch self {
        case .electricIce, .cyberLime: return .electric
        case .solarFlare, .redline: return .fire
        case .midnight, .tunnel: return .smoke
        case .neon, .plasma: return .explosion
        case .aurora, .deepOcean: return .beam
        case .violetStorm: return .frost
        case .warp: return .warp
        // fallback / hybrid
        default: return .plasma
        }
    }
}
