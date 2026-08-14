import SwiftUI

/// Launch-arg gate so Maestro still sees the full dashboard.
enum EtubuMaestroLaunch {
    static var isActive: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-etubuSkipOnboarding")
            || args.contains("etubuSkipOnboarding")
            || args.contains("-etubuForcePremium")
            || args.contains("etubuForcePremium")
            || args.contains("etubuForceLangEn")
            || UserDefaults.standard.bool(forKey: "etubuSkipOnboarding")
    }
}

/// OLED pitch-black speed-only HUD. Tap wakes the full cluster for 10 s.
struct EtubuStealthSpeedView: View {
    let kmh: Int
    let analog: Bool
    var onWake: () -> Void

    /// İğne — ani km/h sıçramasını yumuşatır.
    @State private var needleKmh: Double = 0

    private var targetKmh: Double { Double(max(0, kmh)) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if analog {
                analogGauge
            } else {
                digitalReadout
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onWake() }
        .onAppear { needleKmh = targetKmh }
        .onChange(of: kmh) { _, _ in
            withAnimation(.interpolatingSpring(stiffness: 140, damping: 18)) {
                needleKmh = targetKmh
            }
        }
        .accessibilityIdentifier("etubu.stealth")
        .accessibilityLabel(EtubuClusterL10n.t("stealthMode"))
        .accessibilityHint(EtubuClusterL10n.t("stealthWakeHint"))
        .accessibilityAddTraits(.isButton)
        .accessibilityValue("\(max(0, kmh)) km/h")
    }

    private var digitalReadout: some View {
        VStack(spacing: 6) {
            Text("\(max(0, kmh))")
                .font(.system(size: 128, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.white)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .accessibilityIdentifier("etubu.stealth.speed")
            Text("km/h")
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.45))
                .tracking(4)
        }
    }

    /// 0 solda alt, 220 sağda alt — iğne üst yaydan tarar (klasik analog).
    private let analogMax: Double = 220
    private let analogStartDeg: Double = -135
    private let analogSweepDeg: Double = 270

    private var analogGauge: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height) * 0.88
            ZStack {
                analogFace(size: side)
                analogNeedle(size: side)
                analogHub(size: side)
                VStack(spacing: 0) {
                    Spacer()
                    Text("\(max(0, kmh))")
                        .font(.system(size: max(22, side * 0.11), weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.88))
                        .accessibilityIdentifier("etubu.stealth.speed")
                    Text("km/h")
                        .font(.system(size: max(10, side * 0.038), weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.38))
                        .padding(.bottom, side * 0.16)
                }
                .frame(width: side, height: side)
                .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func analogFace(size: CGFloat) -> some View {
        Canvas { ctx, canvas in
            let c = CGPoint(x: canvas.width * 0.5, y: canvas.height * 0.5)
            let r = size * 0.5
            let outer = r * 0.98
            let majorIn = r * 0.82
            let minorIn = r * 0.88
            let labelR = r * 0.70

            ctx.stroke(
                Path(ellipseIn: CGRect(x: c.x - outer, y: c.y - outer, width: outer * 2, height: outer * 2)),
                with: .color(Color.white.opacity(0.18)),
                lineWidth: 1.2
            )

            let majors = stride(from: 0, through: Int(analogMax), by: 20)
            for v in majors {
                let a = analogAngle(for: Double(v))
                var tick = Path()
                tick.move(to: analogPoint(center: c, radius: majorIn, angleDeg: a))
                tick.addLine(to: analogPoint(center: c, radius: outer, angleDeg: a))
                ctx.stroke(tick, with: .color(.white.opacity(0.92)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))

                let label = Text("\(v)")
                    .font(.system(size: max(11, size * 0.048), weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.78))
                let resolved = ctx.resolve(label)
                let lp = analogPoint(center: c, radius: labelR, angleDeg: a)
                ctx.draw(resolved, at: lp, anchor: .center)
            }

            for v in stride(from: 10, through: Int(analogMax) - 10, by: 20) {
                let a = analogAngle(for: Double(v))
                var tick = Path()
                tick.move(to: analogPoint(center: c, radius: minorIn, angleDeg: a))
                tick.addLine(to: analogPoint(center: c, radius: outer, angleDeg: a))
                ctx.stroke(tick, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
            }
        }
        .frame(width: size, height: size)
    }

    private func analogNeedle(size: CGFloat) -> some View {
        let clamped = min(analogMax, max(0, needleKmh))
        let deg = analogAngle(for: clamped)
        let length = size * 0.42
        let tail = size * 0.11
        let tipW = max(2.2, size * 0.016)
        return NeedleShape(length: length, tail: tail, tipWidth: tipW)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.96, green: 0.20, blue: 0.16),
                        Color.white,
                        Color.white.opacity(0.92),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
            .frame(width: size, height: size)
            .rotationEffect(.degrees(deg))
    }

    private func analogHub(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.12))
                .frame(width: size * 0.14, height: size * 0.14)
            Circle()
                .fill(Color.black)
                .frame(width: size * 0.09, height: size * 0.09)
            Circle()
                .fill(Color.white.opacity(0.88))
                .frame(width: size * 0.038, height: size * 0.038)
        }
        .allowsHitTesting(false)
    }

    private func analogAngle(for kmh: Double) -> Double {
        analogStartDeg + (min(1, max(0, kmh / analogMax)) * analogSweepDeg)
    }

    private func analogPoint(center: CGPoint, radius: CGFloat, angleDeg: Double) -> CGPoint {
        let rad = (-90 + angleDeg) * Double.pi / 180
        return CGPoint(
            x: center.x + radius * CGFloat(cos(rad)),
            y: center.y + radius * CGFloat(sin(rad))
        )
    }
}

/// İğne 12 yönünü gösterir; `rotationEffect` ile döner. Kuyruk + sivri uç.
private struct NeedleShape: Shape {
    var length: CGFloat
    var tail: CGFloat
    var tipWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        p.move(to: CGPoint(x: c.x - tipWidth, y: c.y + tail * 0.15))
        p.addLine(to: CGPoint(x: c.x - tipWidth * 0.35, y: c.y - length))
        p.addLine(to: CGPoint(x: c.x + tipWidth * 0.35, y: c.y - length))
        p.addLine(to: CGPoint(x: c.x + tipWidth, y: c.y + tail * 0.15))
        p.addLine(to: CGPoint(x: c.x + tipWidth * 1.4, y: c.y + tail))
        p.addLine(to: CGPoint(x: c.x - tipWidth * 1.4, y: c.y + tail))
        p.closeSubpath()
        return p
    }
}
